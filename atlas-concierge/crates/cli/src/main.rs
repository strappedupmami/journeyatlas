use std::env;
use std::io::{self, Write};
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{Context, Result};
use atlas_agents::ConciergeAgent;
use atlas_core::{ChatInput, Locale, OpsChecklistType, TripPlanRequest, TripStyle};
use atlas_ml::AtlasMlStack;
use atlas_observability::{AppMetrics, init_tracing};
use atlas_retrieval::HybridRetriever;
use atlas_storage::Store;
use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(name = "concierge")]
#[command(about = "Atlas Concierge CLI")]
struct Cli {
    #[arg(long, default_value = "kb")]
    kb_root: PathBuf,

    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    Chat,
    PlanTrip {
        #[arg(long)]
        style: String,
        #[arg(long, default_value_t = 2)]
        days: u8,
        #[arg(long, default_value = "he")]
        locale: String,
        #[arg(long)]
        people: Option<u8>,
    },
    Ops {
        #[command(subcommand)]
        command: OpsCommand,
    },
    Kb {
        #[command(subcommand)]
        command: KbCommand,
    },
}

#[derive(Debug, Subcommand)]
enum OpsCommand {
    Checklist { kind: String },
}

#[derive(Debug, Subcommand)]
enum KbCommand {
    Search {
        query: String,
        #[arg(long, default_value_t = 5)]
        limit: usize,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing("atlas_cli");
    let cli = Cli::parse();

    let agent = build_agent(&cli.kb_root).await?;

    match cli.command {
        Command::Chat => run_chat(agent).await?,
        Command::PlanTrip {
            style,
            days,
            locale,
            people,
        } => {
            let style = TripStyle::from_str(&style).context("invalid --style value")?;
            let locale = Locale::from_optional_str(Some(&locale));

            let response = agent
                .plan_trip(TripPlanRequest {
                    style,
                    days,
                    locale,
                    people_count: people,
                    constraints: Vec::new(),
                })
                .await?;

            println!("{}", serde_json::to_string_pretty(&response)?);
        }
        Command::Ops { command } => match command {
            OpsCommand::Checklist { kind } => {
                let kind = OpsChecklistType::from_str(&kind).context("invalid checklist kind")?;
                let checklist = agent.ops_checklist(kind).await?;
                println!("{}", serde_json::to_string_pretty(&checklist)?);
            }
        },
        Command::Kb { command } => match command {
            KbCommand::Search { query, limit } => {
                let hits = agent.kb_search(&query, limit);
                println!("{}", serde_json::to_string_pretty(&hits)?);
            }
        },
    }

    Ok(())
}

async fn run_chat(agent: ConciergeAgent<Store>) -> Result<()> {
    let mut session_id: Option<String> = None;

    println!("Atlas Concierge chat mode. type 'exit' to quit.");

    loop {
        print!("> ");
        io::stdout().flush()?;

        let mut line = String::new();
        io::stdin().read_line(&mut line)?;

        let message = line.trim();
        if message.eq_ignore_ascii_case("exit") || message.eq_ignore_ascii_case("quit") {
            break;
        }

        if message.is_empty() {
            continue;
        }

        let reply = agent
            .handle_chat(ChatInput {
                session_id: session_id.clone(),
                text: message.to_string(),
                locale: None,
                user_id: None,
            })
            .await?;

        if let Some(id) = reply
            .json_payload
            .get("session_id")
            .and_then(|value| value.as_str())
            .map(ToString::to_string)
        {
            session_id = Some(id);
        }

        println!("\n{}\n", reply.reply_text);

        if !reply.clarifying_questions.is_empty() {
            println!("Clarifying questions:");
            for question in reply.clarifying_questions {
                println!("- {question}");
            }
            println!();
        }
    }

    Ok(())
}

async fn build_agent(kb_root: &PathBuf) -> Result<ConciergeAgent<Store>> {
    let metrics = AppMetrics::shared();
    let ml_stack = AtlasMlStack::load_default();

    let retriever = Arc::new(
        HybridRetriever::from_kb_dir(kb_root, Some(ml_stack.embedder.clone()))
            .with_context(|| format!("failed loading knowledge base from {}", kb_root.display()))?,
    );

    let store = if let Ok(database_url) = env::var("ATLAS_DATABASE_URL") {
        Store::sqlite(&database_url).await?
    } else {
        Store::memory()
    };

    Ok(ConciergeAgent::new(
        retriever,
        ml_stack,
        atlas_core::PolicySet::default(),
        Arc::new(store),
        metrics,
    ))
}
