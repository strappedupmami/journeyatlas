use aes_gcm::aead::{Aead, OsRng};
use aes_gcm::AeadCore;
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use anyhow::{anyhow, Context, Result};
use atlas_core::{
    EncryptedPayload, FinancialAccessToken, FinancialAccount, FinancialTransaction, Money,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use chrono::{DateTime, Utc};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use sqlx::{Row, SqlitePool};

#[allow(async_fn_in_trait)]
pub trait FinancialRepository: Send + Sync {
    async fn upsert_account(&self, account: &FinancialAccount) -> Result<()>;
    async fn list_accounts(&self, user_id: &str) -> Result<Vec<FinancialAccount>>;
    async fn store_transactions(&self, transactions: &[FinancialTransaction]) -> Result<()>;
    async fn list_transactions_for_window(
        &self,
        user_id: &str,
        since: DateTime<Utc>,
    ) -> Result<Vec<FinancialTransaction>>;
    async fn store_provider_access_token(
        &self,
        user_id: &str,
        provider: &str,
        access_token: &FinancialAccessToken,
    ) -> Result<()>;
    async fn load_provider_access_token(
        &self,
        user_id: &str,
        provider: &str,
    ) -> Result<Option<FinancialAccessToken>>;
}

pub trait FinancialCrypto: Send + Sync {
    fn key_id(&self) -> &str;
    fn encrypt_bytes(&self, plaintext: &[u8]) -> Result<EncryptedPayload>;
    fn decrypt_bytes(&self, payload: &EncryptedPayload) -> Result<Vec<u8>>;

    fn encrypt_json<T: Serialize>(&self, value: &T) -> Result<EncryptedPayload> {
        let plaintext = serde_json::to_vec(value)?;
        self.encrypt_bytes(&plaintext)
    }

    fn decrypt_json<T: DeserializeOwned>(&self, payload: &EncryptedPayload) -> Result<T> {
        let plaintext = self.decrypt_bytes(payload)?;
        Ok(serde_json::from_slice(&plaintext)?)
    }
}

#[derive(Clone)]
pub struct Aes256GcmCrypto {
    key_id: String,
    cipher: Aes256Gcm,
}

impl Aes256GcmCrypto {
    pub fn new(key_id: impl Into<String>, key_bytes: &[u8]) -> Result<Self> {
        if key_bytes.len() != 32 {
            return Err(anyhow!("expected 32-byte AES-256-GCM key"));
        }
        let cipher = Aes256Gcm::new_from_slice(key_bytes)
            .map_err(|_| anyhow!("failed to initialize AES-256-GCM cipher"))?;
        Ok(Self {
            key_id: key_id.into(),
            cipher,
        })
    }
}

impl FinancialCrypto for Aes256GcmCrypto {
    fn key_id(&self) -> &str {
        &self.key_id
    }

    fn encrypt_bytes(&self, plaintext: &[u8]) -> Result<EncryptedPayload> {
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        let ciphertext = self
            .cipher
            .encrypt(&nonce, plaintext)
            .map_err(|_| anyhow!("failed to encrypt financial payload"))?;

        Ok(EncryptedPayload {
            key_id: self.key_id.clone(),
            nonce_b64: STANDARD.encode(nonce),
            ciphertext_b64: STANDARD.encode(ciphertext),
        })
    }

    fn decrypt_bytes(&self, payload: &EncryptedPayload) -> Result<Vec<u8>> {
        let nonce_bytes = STANDARD
            .decode(payload.nonce_b64.as_bytes())
            .context("invalid nonce encoding")?;
        let ciphertext = STANDARD
            .decode(payload.ciphertext_b64.as_bytes())
            .context("invalid ciphertext encoding")?;
        let nonce = Nonce::from_slice(&nonce_bytes);

        self.cipher
            .decrypt(nonce, ciphertext.as_ref())
            .map_err(|_| anyhow!("failed to decrypt financial payload"))
    }
}

#[derive(Clone)]
pub struct SqliteFinancialVault<C>
where
    C: FinancialCrypto + Clone,
{
    pool: SqlitePool,
    crypto: C,
}

impl<C> SqliteFinancialVault<C>
where
    C: FinancialCrypto + Clone,
{
    pub async fn connect(database_url: &str, crypto: C) -> Result<Self> {
        let pool = SqlitePool::connect(database_url)
            .await
            .with_context(|| format!("failed connecting to sqlite at {}", database_url))?;
        let vault = Self { pool, crypto };
        vault.ensure_schema().await?;
        Ok(vault)
    }

    pub async fn from_pool(pool: SqlitePool, crypto: C) -> Result<Self> {
        let vault = Self { pool, crypto };
        vault.ensure_schema().await?;
        Ok(vault)
    }

    pub fn pool(&self) -> &SqlitePool {
        &self.pool
    }

    async fn ensure_schema(&self) -> Result<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS financial_accounts (
              account_id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              provider TEXT NOT NULL,
              provider_account_id TEXT NOT NULL,
              kind TEXT NOT NULL,
              institution_name TEXT,
              display_name TEXT,
              mask_last4 TEXT,
              sensitive_encrypted_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            "#,
        )
        .execute(&self.pool)
        .await?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS financial_transactions (
              transaction_id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              account_id TEXT NOT NULL,
              posted_at TEXT NOT NULL,
              pending INTEGER NOT NULL,
              sensitive_encrypted_json TEXT NOT NULL,
              created_at TEXT NOT NULL
            );
            "#,
        )
        .execute(&self.pool)
        .await?;

        sqlx::query(
            r#"
            CREATE INDEX IF NOT EXISTS idx_financial_transactions_user_posted
            ON financial_transactions (user_id, posted_at);
            "#,
        )
        .execute(&self.pool)
        .await?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS financial_provider_tokens (
              user_id TEXT NOT NULL,
              provider TEXT NOT NULL,
              sensitive_encrypted_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              PRIMARY KEY (user_id, provider)
            );
            "#,
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    fn encode_account_secrets(&self, account: &FinancialAccount) -> Result<String> {
        let secrets = AccountSecrets {
            account_number: account.account_number.clone(),
            available_balance: account.available_balance.clone(),
            current_balance: account.current_balance.clone(),
        };
        Ok(serde_json::to_string(&self.crypto.encrypt_json(&secrets)?)?)
    }

    fn decode_account(&self, row: sqlx::sqlite::SqliteRow) -> Result<FinancialAccount> {
        let payload: EncryptedPayload =
            serde_json::from_str(&row.get::<String, _>("sensitive_encrypted_json"))?;
        let secrets: AccountSecrets = self.crypto.decrypt_json(&payload)?;
        Ok(FinancialAccount {
            account_id: row.get("account_id"),
            user_id: row.get("user_id"),
            provider: row.get("provider"),
            provider_account_id: row.get("provider_account_id"),
            kind: parse_account_kind(row.get::<String, _>("kind").as_str()),
            institution_name: row.get("institution_name"),
            display_name: row.get("display_name"),
            mask_last4: row.get("mask_last4"),
            account_number: secrets.account_number,
            available_balance: secrets.available_balance,
            current_balance: secrets.current_balance,
            created_at: parse_rfc3339(row.get::<String, _>("created_at").as_str())?,
            updated_at: parse_rfc3339(row.get::<String, _>("updated_at").as_str())?,
        })
    }

    fn encode_transaction_secrets(&self, tx: &FinancialTransaction) -> Result<String> {
        let secrets = TransactionSecrets {
            amount: tx.amount.clone(),
            description: tx.description.clone(),
            merchant_name: tx.merchant_name.clone(),
            category: tx.category.clone(),
        };
        Ok(serde_json::to_string(&self.crypto.encrypt_json(&secrets)?)?)
    }

    fn decode_transaction(&self, row: sqlx::sqlite::SqliteRow) -> Result<FinancialTransaction> {
        let payload: EncryptedPayload =
            serde_json::from_str(&row.get::<String, _>("sensitive_encrypted_json"))?;
        let secrets: TransactionSecrets = self.crypto.decrypt_json(&payload)?;
        Ok(FinancialTransaction {
            transaction_id: row.get("transaction_id"),
            user_id: row.get("user_id"),
            account_id: row.get("account_id"),
            posted_at: parse_rfc3339(row.get::<String, _>("posted_at").as_str())?,
            pending: row.get::<i64, _>("pending") > 0,
            amount: secrets.amount,
            description: secrets.description,
            merchant_name: secrets.merchant_name,
            category: secrets.category,
            created_at: parse_rfc3339(row.get::<String, _>("created_at").as_str())?,
        })
    }
}

impl<C> FinancialRepository for SqliteFinancialVault<C>
where
    C: FinancialCrypto + Clone,
{
    async fn upsert_account(&self, account: &FinancialAccount) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO financial_accounts (
              account_id, user_id, provider, provider_account_id, kind, institution_name,
              display_name, mask_last4, sensitive_encrypted_json, created_at, updated_at
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
            ON CONFLICT(account_id) DO UPDATE SET
              user_id=excluded.user_id,
              provider=excluded.provider,
              provider_account_id=excluded.provider_account_id,
              kind=excluded.kind,
              institution_name=excluded.institution_name,
              display_name=excluded.display_name,
              mask_last4=excluded.mask_last4,
              sensitive_encrypted_json=excluded.sensitive_encrypted_json,
              updated_at=excluded.updated_at
            "#,
        )
        .bind(&account.account_id)
        .bind(&account.user_id)
        .bind(&account.provider)
        .bind(&account.provider_account_id)
        .bind(account_kind_str(account))
        .bind(account.institution_name.as_deref())
        .bind(account.display_name.as_deref())
        .bind(account.mask_last4.as_deref())
        .bind(self.encode_account_secrets(account)?)
        .bind(account.created_at.to_rfc3339())
        .bind(account.updated_at.to_rfc3339())
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    async fn list_accounts(&self, user_id: &str) -> Result<Vec<FinancialAccount>> {
        let rows = sqlx::query(
            r#"
            SELECT account_id, user_id, provider, provider_account_id, kind, institution_name,
                   display_name, mask_last4, sensitive_encrypted_json, created_at, updated_at
            FROM financial_accounts
            WHERE user_id = ?1
            ORDER BY updated_at DESC
            "#,
        )
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(|row| self.decode_account(row))
            .collect()
    }

    async fn store_transactions(&self, transactions: &[FinancialTransaction]) -> Result<()> {
        for tx in transactions {
            sqlx::query(
                r#"
                INSERT INTO financial_transactions (
                  transaction_id, user_id, account_id, posted_at, pending,
                  sensitive_encrypted_json, created_at
                )
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                ON CONFLICT(transaction_id) DO UPDATE SET
                  user_id=excluded.user_id,
                  account_id=excluded.account_id,
                  posted_at=excluded.posted_at,
                  pending=excluded.pending,
                  sensitive_encrypted_json=excluded.sensitive_encrypted_json
                "#,
            )
            .bind(&tx.transaction_id)
            .bind(&tx.user_id)
            .bind(&tx.account_id)
            .bind(tx.posted_at.to_rfc3339())
            .bind(i64::from(tx.pending))
            .bind(self.encode_transaction_secrets(tx)?)
            .bind(tx.created_at.to_rfc3339())
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }

    async fn list_transactions_for_window(
        &self,
        user_id: &str,
        since: DateTime<Utc>,
    ) -> Result<Vec<FinancialTransaction>> {
        let rows = sqlx::query(
            r#"
            SELECT transaction_id, user_id, account_id, posted_at, pending,
                   sensitive_encrypted_json, created_at
            FROM financial_transactions
            WHERE user_id = ?1 AND posted_at >= ?2
            ORDER BY posted_at DESC
            "#,
        )
        .bind(user_id)
        .bind(since.to_rfc3339())
        .fetch_all(&self.pool)
        .await?;

        rows.into_iter()
            .map(|row| self.decode_transaction(row))
            .collect()
    }

    async fn store_provider_access_token(
        &self,
        user_id: &str,
        provider: &str,
        access_token: &FinancialAccessToken,
    ) -> Result<()> {
        let encrypted = serde_json::to_string(&self.crypto.encrypt_json(access_token)?)?;
        let now = Utc::now().to_rfc3339();
        sqlx::query(
            r#"
            INSERT INTO financial_provider_tokens (
              user_id, provider, sensitive_encrypted_json, created_at, updated_at
            )
            VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(user_id, provider) DO UPDATE SET
              sensitive_encrypted_json=excluded.sensitive_encrypted_json,
              updated_at=excluded.updated_at
            "#,
        )
        .bind(user_id)
        .bind(provider)
        .bind(encrypted)
        .bind(&now)
        .bind(&now)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    async fn load_provider_access_token(
        &self,
        user_id: &str,
        provider: &str,
    ) -> Result<Option<FinancialAccessToken>> {
        let row = sqlx::query(
            r#"
            SELECT sensitive_encrypted_json
            FROM financial_provider_tokens
            WHERE user_id = ?1 AND provider = ?2
            "#,
        )
        .bind(user_id)
        .bind(provider)
        .fetch_optional(&self.pool)
        .await?;

        let Some(row) = row else {
            return Ok(None);
        };
        let payload: EncryptedPayload =
            serde_json::from_str(&row.get::<String, _>("sensitive_encrypted_json"))?;
        Ok(Some(self.crypto.decrypt_json(&payload)?))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AccountSecrets {
    account_number: Option<String>,
    available_balance: Option<Money>,
    current_balance: Option<Money>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TransactionSecrets {
    amount: Money,
    description: String,
    merchant_name: Option<String>,
    category: Option<String>,
}

fn parse_rfc3339(value: &str) -> Result<DateTime<Utc>> {
    Ok(DateTime::parse_from_rfc3339(value)?.with_timezone(&Utc))
}

fn parse_account_kind(value: &str) -> atlas_core::FinancialAccountKind {
    match value {
        "checking" => atlas_core::FinancialAccountKind::Checking,
        "savings" => atlas_core::FinancialAccountKind::Savings,
        "investment" => atlas_core::FinancialAccountKind::Investment,
        "credit" => atlas_core::FinancialAccountKind::Credit,
        _ => atlas_core::FinancialAccountKind::Unknown,
    }
}

fn account_kind_str(account: &FinancialAccount) -> &'static str {
    match account.kind {
        atlas_core::FinancialAccountKind::Checking => "checking",
        atlas_core::FinancialAccountKind::Savings => "savings",
        atlas_core::FinancialAccountKind::Investment => "investment",
        atlas_core::FinancialAccountKind::Credit => "credit",
        atlas_core::FinancialAccountKind::Unknown => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use atlas_core::FinancialAccountKind;
    use chrono::Duration;

    fn crypto() -> Aes256GcmCrypto {
        Aes256GcmCrypto::new("test-key", &[7_u8; 32]).expect("valid key")
    }

    fn sample_account() -> FinancialAccount {
        FinancialAccount {
            account_id: "acct-1".to_string(),
            user_id: "user-1".to_string(),
            provider: "plaid".to_string(),
            provider_account_id: "provider-acct-1".to_string(),
            kind: FinancialAccountKind::Checking,
            institution_name: Some("Atlas Bank".to_string()),
            display_name: Some("Main Checking".to_string()),
            mask_last4: Some("4242".to_string()),
            account_number: Some("123456789".to_string()),
            available_balance: Some(Money::new("USD", 123_45)),
            current_balance: Some(Money::new("USD", 150_00)),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        }
    }

    fn sample_tx() -> FinancialTransaction {
        FinancialTransaction {
            transaction_id: "tx-1".to_string(),
            user_id: "user-1".to_string(),
            account_id: "acct-1".to_string(),
            posted_at: Utc::now() - Duration::days(1),
            pending: false,
            amount: Money::new("USD", -45_67),
            description: "Amazon Marketplace".to_string(),
            merchant_name: Some("Amazon".to_string()),
            category: Some("shopping".to_string()),
            created_at: Utc::now(),
        }
    }

    #[tokio::test]
    async fn vault_encrypts_and_restores_sensitive_financial_rows() {
        let vault = SqliteFinancialVault::connect("sqlite::memory:", crypto())
            .await
            .expect("vault should connect");
        let account = sample_account();
        let tx = sample_tx();

        vault
            .upsert_account(&account)
            .await
            .expect("account stored");
        vault
            .store_transactions(std::slice::from_ref(&tx))
            .await
            .expect("tx stored");

        let accounts = vault
            .list_accounts("user-1")
            .await
            .expect("accounts listed");
        let transactions = vault
            .list_transactions_for_window("user-1", Utc::now() - Duration::days(7))
            .await
            .expect("transactions listed");

        assert_eq!(accounts[0].account_number.as_deref(), Some("123456789"));
        assert_eq!(transactions[0].description, "Amazon Marketplace");

        let row = sqlx::query(
            "SELECT sensitive_encrypted_json FROM financial_transactions WHERE transaction_id = ?1",
        )
        .bind("tx-1")
        .fetch_one(vault.pool())
        .await
        .expect("encrypted row");
        let raw: String = row.get("sensitive_encrypted_json");
        assert!(!raw.contains("Amazon Marketplace"));
        assert!(!raw.contains("-45_67"));
    }

    #[tokio::test]
    async fn vault_encrypts_provider_tokens() {
        let vault = SqliteFinancialVault::connect("sqlite::memory:", crypto())
            .await
            .expect("vault should connect");
        let token = FinancialAccessToken {
            access_token: "secret-access-token".to_string(),
            item_id: Some("item-1".to_string()),
            institution_id: Some("ins-1".to_string()),
            scopes: vec!["transactions".to_string()],
        };

        vault
            .store_provider_access_token("user-1", "plaid", &token)
            .await
            .expect("token stored");

        let loaded = vault
            .load_provider_access_token("user-1", "plaid")
            .await
            .expect("token loaded")
            .expect("token present");
        assert_eq!(loaded.access_token, "secret-access-token");
    }
}
