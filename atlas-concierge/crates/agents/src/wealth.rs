use std::sync::Arc;
use std::time::Duration as StdDuration;

use anyhow::Result;
use atlas_core::{
    calculate_safe_sweep_amount, detect_stress_spending, BankLinkSession, BankLinkSessionRequest,
    BankProvider, BankTokenExchangeRequest, StressSpendingSignal, SweepRecommendation,
};
use atlas_storage::FinancialRepository;
use chrono::{Duration, Utc};

#[derive(Debug, Clone)]
pub struct WealthAutomationCycle {
    pub sweep_recommendation: SweepRecommendation,
    pub stress_signal: StressSpendingSignal,
}

#[derive(Clone)]
pub struct WealthBabysitter<R>
where
    R: FinancialRepository,
{
    repository: Arc<R>,
}

impl<R> WealthBabysitter<R>
where
    R: FinancialRepository + 'static,
{
    pub fn new(repository: Arc<R>) -> Self {
        Self { repository }
    }

    pub async fn calculate_safe_sweep_amount(&self, user_id: &str) -> Result<SweepRecommendation> {
        let accounts = self.repository.list_accounts(user_id).await?;
        let transactions = self
            .repository
            .list_transactions_for_window(user_id, Utc::now() - Duration::days(60))
            .await?;
        Ok(calculate_safe_sweep_amount(
            Utc::now(),
            &accounts,
            &transactions,
        ))
    }

    pub async fn detect_stress_spending(&self, user_id: &str) -> Result<StressSpendingSignal> {
        let transactions = self
            .repository
            .list_transactions_for_window(user_id, Utc::now() - Duration::days(60))
            .await?;
        Ok(detect_stress_spending(Utc::now(), &transactions))
    }

    pub async fn run_once(&self, user_id: &str) -> Result<WealthAutomationCycle> {
        let sweep_recommendation = self.calculate_safe_sweep_amount(user_id).await?;
        let stress_signal = self.detect_stress_spending(user_id).await?;
        Ok(WealthAutomationCycle {
            sweep_recommendation,
            stress_signal,
        })
    }

    pub async fn run_scheduler(&self, user_ids: &[String], cadence: StdDuration) {
        let mut interval = tokio::time::interval(cadence);
        loop {
            interval.tick().await;
            for user_id in user_ids {
                let _ = self.run_once(user_id).await;
            }
        }
    }
}

#[derive(Clone)]
pub struct BankLinkOrchestrator<R, B>
where
    R: FinancialRepository,
    B: BankProvider,
{
    repository: Arc<R>,
    provider: Arc<B>,
}

impl<R, B> BankLinkOrchestrator<R, B>
where
    R: FinancialRepository,
    B: BankProvider,
{
    pub fn new(repository: Arc<R>, provider: Arc<B>) -> Self {
        Self {
            repository,
            provider,
        }
    }

    pub async fn start_link(&self, request: BankLinkSessionRequest) -> Result<BankLinkSession> {
        self.provider.create_link_session(request).await
    }

    pub async fn exchange_public_token(&self, request: BankTokenExchangeRequest) -> Result<usize> {
        let access_token = self.provider.exchange_public_token(request.clone()).await?;
        self.repository
            .store_provider_access_token(&request.user_id, &request.provider, &access_token)
            .await?;
        let snapshot = self
            .provider
            .fetch_account_snapshot(&request.user_id, &access_token)
            .await?;

        for account in &snapshot.accounts {
            self.repository.upsert_account(account).await?;
        }
        self.repository
            .store_transactions(&snapshot.transactions)
            .await?;

        Ok(snapshot.accounts.len())
    }
}
