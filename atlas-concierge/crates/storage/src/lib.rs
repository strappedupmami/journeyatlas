use std::collections::HashMap;
use std::sync::Arc;

use anyhow::{Context, Result};
use atlas_core::{ConversationSession, Locale};
use chrono::{DateTime, Utc};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqlitePool};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GearInventoryItem {
    pub sku: String,
    pub name: String,
    pub quantity: i32,
    pub minimum_required: i32,
}

pub trait SessionRepository: Send + Sync {
    async fn load_session(&self, session_id: &str) -> Result<Option<ConversationSession>>;
    async fn upsert_session(&self, session: &ConversationSession) -> Result<()>;
    async fn purge_expired(&self, now: DateTime<Utc>) -> Result<u64>;
}

pub trait InventoryRepository: Send + Sync {
    async fn list_inventory(&self) -> Result<Vec<GearInventoryItem>>;
    async fn upsert_inventory_item(&self, item: GearInventoryItem) -> Result<()>;
}

#[derive(Clone, Default)]
pub struct MemoryStore {
    sessions: Arc<RwLock<HashMap<String, ConversationSession>>>,
    inventory: Arc<RwLock<HashMap<String, GearInventoryItem>>>,
}

impl MemoryStore {
    pub fn new() -> Self {
        Self::default()
    }
}

impl SessionRepository for MemoryStore {
    async fn load_session(&self, session_id: &str) -> Result<Option<ConversationSession>> {
        Ok(self.sessions.read().get(session_id).cloned())
    }

    async fn upsert_session(&self, session: &ConversationSession) -> Result<()> {
        self.sessions
            .write()
            .insert(session.session_id.clone(), session.clone());
        Ok(())
    }

    async fn purge_expired(&self, now: DateTime<Utc>) -> Result<u64> {
        let mut removed = 0_u64;
        self.sessions.write().retain(|_, value| {
            let keep = value.expires_at > now;
            if !keep {
                removed += 1;
            }
            keep
        });

        Ok(removed)
    }
}

impl InventoryRepository for MemoryStore {
    async fn list_inventory(&self) -> Result<Vec<GearInventoryItem>> {
        Ok(self.inventory.read().values().cloned().collect())
    }

    async fn upsert_inventory_item(&self, item: GearInventoryItem) -> Result<()> {
        self.inventory.write().insert(item.sku.clone(), item);
        Ok(())
    }
}

#[derive(Clone)]
pub struct SqliteStore {
    pool: SqlitePool,
}

impl SqliteStore {
    pub async fn connect(database_url: &str) -> Result<Self> {
        let pool = SqlitePool::connect(database_url)
            .await
            .with_context(|| format!("failed connecting to sqlite at {}", database_url))?;

        let store = Self { pool };
        store.ensure_schema().await?;
        Ok(store)
    }

    pub fn pool(&self) -> &SqlitePool {
        &self.pool
    }

    async fn ensure_schema(&self) -> Result<()> {
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS sessions (
              session_id TEXT PRIMARY KEY,
              user_id TEXT,
              locale TEXT NOT NULL,
              expires_at TEXT NOT NULL,
              turns_json TEXT NOT NULL
            );
            "#,
        )
        .execute(&self.pool)
        .await?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS inventory_items (
              sku TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              quantity INTEGER NOT NULL,
              minimum_required INTEGER NOT NULL
            );
            "#,
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}

impl SessionRepository for SqliteStore {
    async fn load_session(&self, session_id: &str) -> Result<Option<ConversationSession>> {
        let row = sqlx::query(
            r#"
            SELECT session_id, user_id, locale, expires_at, turns_json
            FROM sessions
            WHERE session_id = ?1
            "#,
        )
        .bind(session_id)
        .fetch_optional(&self.pool)
        .await?;

        let Some(row) = row else {
            return Ok(None);
        };

        let locale = Locale::from_optional_str(Some(row.get::<String, _>("locale").as_str()));
        let turns_json: String = row.get("turns_json");
        let turns = serde_json::from_str(&turns_json).unwrap_or_default();

        let session = ConversationSession {
            session_id: row.get("session_id"),
            user_id: row.get("user_id"),
            locale,
            expires_at: row
                .get::<String, _>("expires_at")
                .parse()
                .unwrap_or_else(|_| Utc::now()),
            turns,
        };

        Ok(Some(session))
    }

    async fn upsert_session(&self, session: &ConversationSession) -> Result<()> {
        let turns_json = serde_json::to_string(&session.turns)?;

        sqlx::query(
            r#"
            INSERT INTO sessions (session_id, user_id, locale, expires_at, turns_json)
            VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(session_id) DO UPDATE SET
              user_id=excluded.user_id,
              locale=excluded.locale,
              expires_at=excluded.expires_at,
              turns_json=excluded.turns_json
            "#,
        )
        .bind(&session.session_id)
        .bind(&session.user_id)
        .bind(session.locale.as_code())
        .bind(session.expires_at.to_rfc3339())
        .bind(turns_json)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    async fn purge_expired(&self, now: DateTime<Utc>) -> Result<u64> {
        let result = sqlx::query("DELETE FROM sessions WHERE expires_at < ?1")
            .bind(now.to_rfc3339())
            .execute(&self.pool)
            .await?;

        Ok(result.rows_affected())
    }
}

impl InventoryRepository for SqliteStore {
    async fn list_inventory(&self) -> Result<Vec<GearInventoryItem>> {
        let rows = sqlx::query(
            r#"
            SELECT sku, name, quantity, minimum_required
            FROM inventory_items
            ORDER BY sku
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        let items = rows
            .into_iter()
            .map(|row| GearInventoryItem {
                sku: row.get("sku"),
                name: row.get("name"),
                quantity: row.get("quantity"),
                minimum_required: row.get("minimum_required"),
            })
            .collect();

        Ok(items)
    }

    async fn upsert_inventory_item(&self, item: GearInventoryItem) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO inventory_items (sku, name, quantity, minimum_required)
            VALUES (?1, ?2, ?3, ?4)
            ON CONFLICT(sku) DO UPDATE SET
              name=excluded.name,
              quantity=excluded.quantity,
              minimum_required=excluded.minimum_required
            "#,
        )
        .bind(&item.sku)
        .bind(&item.name)
        .bind(item.quantity)
        .bind(item.minimum_required)
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}

#[derive(Clone)]
pub enum Store {
    Memory(MemoryStore),
    Sqlite(SqliteStore),
}

impl Store {
    pub fn memory() -> Self {
        Self::Memory(MemoryStore::new())
    }

    pub async fn sqlite(database_url: &str) -> Result<Self> {
        let sqlite = SqliteStore::connect(database_url).await?;
        Ok(Self::Sqlite(sqlite))
    }
}

impl SessionRepository for Store {
    async fn load_session(&self, session_id: &str) -> Result<Option<ConversationSession>> {
        match self {
            Store::Memory(store) => store.load_session(session_id).await,
            Store::Sqlite(store) => store.load_session(session_id).await,
        }
    }

    async fn upsert_session(&self, session: &ConversationSession) -> Result<()> {
        match self {
            Store::Memory(store) => store.upsert_session(session).await,
            Store::Sqlite(store) => store.upsert_session(session).await,
        }
    }

    async fn purge_expired(&self, now: DateTime<Utc>) -> Result<u64> {
        match self {
            Store::Memory(store) => store.purge_expired(now).await,
            Store::Sqlite(store) => store.purge_expired(now).await,
        }
    }
}

impl InventoryRepository for Store {
    async fn list_inventory(&self) -> Result<Vec<GearInventoryItem>> {
        match self {
            Store::Memory(store) => store.list_inventory().await,
            Store::Sqlite(store) => store.list_inventory().await,
        }
    }

    async fn upsert_inventory_item(&self, item: GearInventoryItem) -> Result<()> {
        match self {
            Store::Memory(store) => store.upsert_inventory_item(item).await,
            Store::Sqlite(store) => store.upsert_inventory_item(item).await,
        }
    }
}
