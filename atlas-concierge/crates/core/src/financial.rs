use anyhow::Result;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Money {
    pub currency: String,
    pub cents: i64,
}

impl Money {
    pub fn new(currency: impl Into<String>, cents: i64) -> Self {
        Self {
            currency: currency.into(),
            cents,
        }
    }

    pub fn zero(currency: impl Into<String>) -> Self {
        Self::new(currency, 0)
    }

    pub fn checked_add(&self, other: &Self) -> Option<Self> {
        (self.currency == other.currency)
            .then_some(self.cents.checked_add(other.cents))
            .flatten()
            .map(|cents| Self::new(self.currency.clone(), cents))
    }

    pub fn checked_sub(&self, other: &Self) -> Option<Self> {
        (self.currency == other.currency)
            .then_some(self.cents.checked_sub(other.cents))
            .flatten()
            .map(|cents| Self::new(self.currency.clone(), cents))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EncryptedPayload {
    pub key_id: String,
    pub nonce_b64: String,
    pub ciphertext_b64: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FinancialAccountKind {
    Checking,
    Savings,
    Investment,
    Credit,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FinancialAccount {
    pub account_id: String,
    pub user_id: String,
    pub provider: String,
    pub provider_account_id: String,
    pub kind: FinancialAccountKind,
    pub institution_name: Option<String>,
    pub display_name: Option<String>,
    pub mask_last4: Option<String>,
    pub account_number: Option<String>,
    pub available_balance: Option<Money>,
    pub current_balance: Option<Money>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FinancialTransaction {
    pub transaction_id: String,
    pub user_id: String,
    pub account_id: String,
    pub posted_at: DateTime<Utc>,
    pub pending: bool,
    pub amount: Money,
    pub description: String,
    pub merchant_name: Option<String>,
    pub category: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FinancialAccessToken {
    pub access_token: String,
    pub item_id: Option<String>,
    pub institution_id: Option<String>,
    pub scopes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BankLinkSessionRequest {
    pub user_id: String,
    pub provider: String,
    pub redirect_uri: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BankLinkSession {
    pub provider: String,
    pub link_token: String,
    pub authorization_url: Option<String>,
    pub expires_at: DateTime<Utc>,
    pub state: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BankTokenExchangeRequest {
    pub user_id: String,
    pub provider: String,
    pub public_token: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BankAccountSnapshot {
    pub accounts: Vec<FinancialAccount>,
    pub transactions: Vec<FinancialTransaction>,
}

#[allow(async_fn_in_trait)]
pub trait BankProvider: Send + Sync {
    async fn create_link_session(&self, request: BankLinkSessionRequest)
        -> Result<BankLinkSession>;

    async fn exchange_public_token(
        &self,
        request: BankTokenExchangeRequest,
    ) -> Result<FinancialAccessToken>;

    async fn fetch_account_snapshot(
        &self,
        user_id: &str,
        access_token: &FinancialAccessToken,
    ) -> Result<BankAccountSnapshot>;
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecurringCost {
    pub merchant: String,
    pub amount: Money,
    pub confidence: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SweepRecommendation {
    pub amount: Money,
    pub reserve_buffer: Money,
    pub recurring_costs: Vec<RecurringCost>,
    pub rationale: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StressSpendingSeverity {
    None,
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StressSpendingSignal {
    pub detected: bool,
    pub severity: StressSpendingSeverity,
    pub recent_nonessential_spend: Money,
    pub baseline_nonessential_spend: Money,
    pub recent_nonessential_count: usize,
    pub baseline_nonessential_count: f32,
    pub suggested_card_pause_hours: Option<u16>,
    pub triggers: Vec<String>,
}

pub fn calculate_safe_sweep_amount(
    now: DateTime<Utc>,
    accounts: &[FinancialAccount],
    transactions: &[FinancialTransaction],
) -> SweepRecommendation {
    let currency = transactions
        .first()
        .map(|tx| tx.amount.currency.clone())
        .or_else(|| {
            accounts
                .iter()
                .find_map(|account| account.available_balance.as_ref())
                .map(|money| money.currency.clone())
        })
        .unwrap_or_else(|| "USD".to_string());
    let thirty_days_ago = now - Duration::days(30);

    let liquid_balance_cents: i64 = accounts
        .iter()
        .filter(|account| {
            matches!(
                account.kind,
                FinancialAccountKind::Checking | FinancialAccountKind::Savings
            )
        })
        .filter_map(|account| {
            account
                .available_balance
                .as_ref()
                .or(account.current_balance.as_ref())
        })
        .filter(|money| money.currency == currency)
        .map(|money| money.cents)
        .sum();

    let recent: Vec<&FinancialTransaction> = transactions
        .iter()
        .filter(|tx| {
            !tx.pending && tx.posted_at >= thirty_days_ago && tx.amount.currency == currency
        })
        .collect();

    let monthly_income_cents: i64 = recent
        .iter()
        .filter(|tx| tx.amount.cents > 0)
        .map(|tx| tx.amount.cents)
        .sum();

    let recurring_costs = detect_recurring_costs(&currency, &recent);
    let recurring_total_cents: i64 = recurring_costs.iter().map(|cost| cost.amount.cents).sum();
    let income_buffer_cents = ((monthly_income_cents as f64) * 0.20).round() as i64;
    let reserve_buffer_cents = recurring_total_cents.max(income_buffer_cents).max(50_00);
    let capped_sweep_cents = (monthly_income_cents / 5).max(0);
    let safe_surplus_cents = (liquid_balance_cents - recurring_total_cents - reserve_buffer_cents)
        .max(0)
        .min(capped_sweep_cents.max(liquid_balance_cents.max(0)));

    let mut rationale = vec![
        "Calculated from the last 30 days of settled transactions.".to_string(),
        "Recurring fixed costs were reserved before proposing any sweep.".to_string(),
        "The safety buffer preserves runway against overdrafts and pay-cycle variance.".to_string(),
    ];
    if safe_surplus_cents == 0 {
        rationale.push(
            "No safe sweep was recommended because liquid balance did not clear the required buffer."
                .to_string(),
        );
    }

    SweepRecommendation {
        amount: Money::new(currency.clone(), safe_surplus_cents),
        reserve_buffer: Money::new(currency.clone(), reserve_buffer_cents),
        recurring_costs,
        rationale,
    }
}

pub fn detect_stress_spending(
    now: DateTime<Utc>,
    transactions: &[FinancialTransaction],
) -> StressSpendingSignal {
    let currency = transactions
        .first()
        .map(|tx| tx.amount.currency.clone())
        .unwrap_or_else(|| "USD".to_string());
    let recent_start = now - Duration::days(7);
    let baseline_start = now - Duration::days(35);

    let recent: Vec<&FinancialTransaction> = transactions
        .iter()
        .filter(|tx| {
            !tx.pending
                && tx.amount.currency == currency
                && tx.posted_at >= recent_start
                && is_nonessential(tx)
        })
        .collect();

    let baseline: Vec<&FinancialTransaction> = transactions
        .iter()
        .filter(|tx| {
            !tx.pending
                && tx.amount.currency == currency
                && tx.posted_at >= baseline_start
                && tx.posted_at < recent_start
                && is_nonessential(tx)
        })
        .collect();

    let recent_spend_cents: i64 = recent.iter().map(|tx| tx.amount.cents.abs()).sum();
    let baseline_spend_cents: i64 = baseline.iter().map(|tx| tx.amount.cents.abs()).sum();
    let recent_count = recent.len();
    let baseline_count = baseline.len() as f32 / 4.0;
    let normalized_baseline_spend = baseline_spend_cents as f32 / 4.0;

    let amount_ratio = if normalized_baseline_spend <= 0.0 {
        if recent_spend_cents > 0 {
            10.0
        } else {
            0.0
        }
    } else {
        recent_spend_cents as f32 / normalized_baseline_spend
    };
    let count_ratio = if baseline_count <= 0.0 {
        if recent_count > 0 {
            10.0
        } else {
            0.0
        }
    } else {
        recent_count as f32 / baseline_count
    };

    let severity = if amount_ratio >= 2.5 || count_ratio >= 2.5 {
        StressSpendingSeverity::High
    } else if amount_ratio >= 1.8 || count_ratio >= 1.8 {
        StressSpendingSeverity::Medium
    } else if amount_ratio >= 1.3 || count_ratio >= 1.3 {
        StressSpendingSeverity::Low
    } else {
        StressSpendingSeverity::None
    };

    let triggers = top_nonessential_triggers(&recent);
    let detected = severity != StressSpendingSeverity::None;
    let suggested_card_pause_hours = match severity {
        StressSpendingSeverity::High => Some(24),
        StressSpendingSeverity::Medium => Some(12),
        StressSpendingSeverity::Low => Some(6),
        StressSpendingSeverity::None => None,
    };

    StressSpendingSignal {
        detected,
        severity,
        recent_nonessential_spend: Money::new(currency.clone(), recent_spend_cents),
        baseline_nonessential_spend: Money::new(currency, normalized_baseline_spend.round() as i64),
        recent_nonessential_count: recent_count,
        baseline_nonessential_count: baseline_count,
        suggested_card_pause_hours,
        triggers,
    }
}

fn detect_recurring_costs(currency: &str, recent: &[&FinancialTransaction]) -> Vec<RecurringCost> {
    let mut buckets: HashMap<String, Vec<i64>> = HashMap::new();
    for tx in recent {
        if tx.amount.cents >= 0 {
            continue;
        }
        let key = recurring_key(tx);
        if key.is_empty() {
            continue;
        }
        buckets.entry(key).or_default().push(tx.amount.cents.abs());
    }

    let mut costs = buckets
        .into_iter()
        .filter_map(|(merchant, amounts)| {
            (amounts.len() >= 2).then(|| {
                let avg_cents = amounts.iter().sum::<i64>() / amounts.len() as i64;
                let min = *amounts.iter().min().unwrap_or(&avg_cents);
                let max = *amounts.iter().max().unwrap_or(&avg_cents);
                let variance = if max == 0 {
                    0.0
                } else {
                    (max - min) as f32 / max as f32
                };
                let confidence = (1.0 - variance).clamp(0.25, 0.95);
                RecurringCost {
                    merchant,
                    amount: Money::new(currency.to_string(), avg_cents),
                    confidence,
                }
            })
        })
        .collect::<Vec<_>>();

    costs.sort_by(|left, right| right.amount.cents.cmp(&left.amount.cents));
    costs
}

fn recurring_key(tx: &FinancialTransaction) -> String {
    tx.merchant_name
        .clone()
        .or_else(|| Some(tx.description.clone()))
        .unwrap_or_default()
        .trim()
        .to_lowercase()
}

fn is_nonessential(tx: &FinancialTransaction) -> bool {
    if tx.amount.cents >= 0 {
        return false;
    }
    let haystack = format!(
        "{} {}",
        tx.description.to_lowercase(),
        tx.category.clone().unwrap_or_default().to_lowercase()
    );
    [
        "takeout",
        "ubereats",
        "uber eats",
        "doordash",
        "amazon",
        "shopping",
        "delivery",
        "entertainment",
        "ride share",
        "rideshare",
        "lyft",
        "uber",
        "coffee",
    ]
    .iter()
    .any(|needle| haystack.contains(needle))
}

fn top_nonessential_triggers(recent: &[&FinancialTransaction]) -> Vec<String> {
    let mut counts: HashMap<String, usize> = HashMap::new();
    for tx in recent {
        let key = tx
            .merchant_name
            .clone()
            .unwrap_or_else(|| tx.description.clone());
        *counts.entry(key).or_default() += 1;
    }

    let mut triggers = counts.into_iter().collect::<Vec<_>>();
    triggers.sort_by(|left, right| right.1.cmp(&left.1));
    triggers
        .into_iter()
        .take(3)
        .map(|(merchant, count)| {
            format!("{merchant} appeared {count} times in recent discretionary spending.")
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn account(account_id: &str, balance_cents: i64) -> FinancialAccount {
        FinancialAccount {
            account_id: account_id.to_string(),
            user_id: "user-1".to_string(),
            provider: "plaid".to_string(),
            provider_account_id: account_id.to_string(),
            kind: FinancialAccountKind::Checking,
            institution_name: Some("Bank".to_string()),
            display_name: Some("Main".to_string()),
            mask_last4: Some("1234".to_string()),
            account_number: Some("00001234".to_string()),
            available_balance: Some(Money::new("USD", balance_cents)),
            current_balance: Some(Money::new("USD", balance_cents)),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        }
    }

    fn tx(days_ago: i64, cents: i64, description: &str, category: &str) -> FinancialTransaction {
        FinancialTransaction {
            transaction_id: format!("tx-{days_ago}-{cents}"),
            user_id: "user-1".to_string(),
            account_id: "acct-1".to_string(),
            posted_at: Utc::now() - Duration::days(days_ago),
            pending: false,
            amount: Money::new("USD", cents),
            description: description.to_string(),
            merchant_name: Some(description.to_string()),
            category: Some(category.to_string()),
            created_at: Utc::now(),
        }
    }

    #[test]
    fn sweep_amount_reserves_fixed_costs_and_buffer() {
        let recommendation = calculate_safe_sweep_amount(
            Utc::now(),
            &[account("acct-1", 300_000)],
            &[
                tx(2, 250_000, "Payroll", "income"),
                tx(3, -12_000, "Rent", "housing"),
                tx(15, -12_000, "Rent", "housing"),
                tx(7, -8_000, "Utilities", "utilities"),
                tx(21, -8_000, "Utilities", "utilities"),
            ],
        );

        assert!(recommendation.amount.cents > 0);
        assert!(recommendation.reserve_buffer.cents >= 50_000);
        assert_eq!(recommendation.recurring_costs.len(), 2);
    }

    #[test]
    fn stress_spending_flags_recent_spike() {
        let signal = detect_stress_spending(
            Utc::now(),
            &[
                tx(2, -4_000, "Amazon", "shopping"),
                tx(1, -3_500, "UberEats", "takeout"),
                tx(5, -2_900, "DoorDash", "delivery"),
                tx(28, -1_200, "Amazon", "shopping"),
                tx(24, -900, "Coffee", "coffee"),
            ],
        );

        assert!(signal.detected);
        assert_ne!(signal.severity, StressSpendingSeverity::None);
        assert!(!signal.triggers.is_empty());
    }
}
