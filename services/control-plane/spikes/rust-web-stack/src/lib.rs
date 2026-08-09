// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Disposable C-004 framework spike. This is evidence, not a production service.

use std::{
    net::SocketAddr,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use axum::{
    Router,
    extract::{
        State, WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    http::{HeaderMap, StatusCode},
    response::Response,
    routing::get,
};
use futures_util::{SinkExt, StreamExt};
use tokio::{net::TcpListener, sync::mpsc, task::JoinHandle};
use tokio_util::sync::CancellationToken;
use tracing::{Instrument, info_span};

pub const SPIKE_AUTHORIZATION: &str = "Bearer c004-spike-token";
const OUTBOUND_CAPACITY: usize = 8;

#[derive(Clone, Default)]
struct AppState {
    active_connections: Arc<AtomicUsize>,
    saturated_queues: Arc<AtomicUsize>,
}

/// Observable counters exposed to the test harness without logging content.
#[derive(Clone, Default)]
pub struct SpikeMetrics(AppState);

impl SpikeMetrics {
    pub fn active_connections(&self) -> usize {
        self.0.active_connections.load(Ordering::SeqCst)
    }

    pub fn saturated_queues(&self) -> usize {
        self.0.saturated_queues.load(Ordering::SeqCst)
    }
}

pub struct SpikeServer {
    pub address: SocketAddr,
    pub metrics: SpikeMetrics,
    cancellation: CancellationToken,
    task: JoinHandle<std::io::Result<()>>,
}

impl SpikeServer {
    pub async fn start() -> std::io::Result<Self> {
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        let address = listener.local_addr()?;
        let state = AppState::default();
        let cancellation = CancellationToken::new();
        let shutdown = cancellation.clone();
        let app = Router::new()
            .route("/health", get(|| async { StatusCode::NO_CONTENT }))
            .route("/socket", get(socket_route))
            .with_state(state.clone());

        let task = tokio::spawn(async move {
            axum::serve(listener, app)
                .with_graceful_shutdown(shutdown.cancelled_owned())
                .await
        });

        Ok(Self {
            address,
            metrics: SpikeMetrics(state),
            cancellation,
            task,
        })
    }

    pub async fn shutdown(self) -> std::io::Result<()> {
        self.cancellation.cancel();
        self.task.await.expect("server task panicked")
    }
}

async fn socket_route(
    State(state): State<AppState>,
    headers: HeaderMap,
    upgrade: WebSocketUpgrade,
) -> Result<Response, StatusCode> {
    if headers
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        != Some(SPIKE_AUTHORIZATION)
    {
        return Err(StatusCode::UNAUTHORIZED);
    }

    Ok(upgrade.on_upgrade(move |socket| {
        serve_socket(socket, state).instrument(info_span!("websocket", transport = "axum"))
    }))
}

async fn serve_socket(socket: WebSocket, state: AppState) {
    state.active_connections.fetch_add(1, Ordering::SeqCst);
    let (mut writer, mut reader) = socket.split();
    let (outbound_tx, mut outbound_rx) = mpsc::channel(OUTBOUND_CAPACITY);
    let writer_task = tokio::spawn(async move {
        while let Some(message) = outbound_rx.recv().await {
            // A small delay makes bounded-queue behavior deterministic in the spike harness.
            tokio::time::sleep(Duration::from_millis(1)).await;
            if writer.send(message).await.is_err() {
                break;
            }
        }
    });

    while let Some(Ok(message)) = reader.next().await {
        match message {
            Message::Text(_) | Message::Binary(_) => {
                if outbound_tx.try_send(message).is_err() {
                    state.saturated_queues.fetch_add(1, Ordering::SeqCst);
                    break;
                }
            }
            Message::Close(_) => break,
            Message::Ping(payload) => {
                if outbound_tx.try_send(Message::Pong(payload)).is_err() {
                    state.saturated_queues.fetch_add(1, Ordering::SeqCst);
                    break;
                }
            }
            Message::Pong(_) => {}
        }
    }

    drop(outbound_tx);
    let _ = writer_task.await;
    state.active_connections.fetch_sub(1, Ordering::SeqCst);
}
