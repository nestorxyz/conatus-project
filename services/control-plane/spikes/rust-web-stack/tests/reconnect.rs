// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

use std::{
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use conatus_rust_web_stack_spike::{SPIKE_AUTHORIZATION, SpikeServer};
use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{Error, Message, client::IntoClientRequest, http::HeaderValue},
};
use tracing_subscriber::{layer::SubscriberExt, registry::Registry};

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn authenticated_clients_reconnect_under_load_and_shutdown_cleanly() {
    let server = SpikeServer::start().await.expect("server starts");
    let mut clients = Vec::new();

    for client in 0..32_u8 {
        let address = server.address;
        clients.push(tokio::spawn(async move {
            for reconnect in 0..3_u8 {
                let (mut socket, response) = connect_async(authenticated_request(address))
                    .await
                    .expect("authenticated connection succeeds");
                assert_eq!(response.status(), 101);
                let payload = vec![client, reconnect];
                socket
                    .send(Message::Binary(payload.clone().into()))
                    .await
                    .unwrap();
                assert_eq!(
                    socket.next().await.unwrap().unwrap(),
                    Message::Binary(payload.into())
                );
                socket.close(None).await.unwrap();
            }
        }));
    }

    tokio::time::timeout(Duration::from_secs(10), async {
        for client in clients {
            client.await.unwrap();
        }
    })
    .await
    .expect("load/reconnect harness stays within its budget");

    tokio::time::timeout(Duration::from_secs(2), async {
        while server.metrics.active_connections() != 0 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("connections drain");
    server.shutdown().await.expect("graceful shutdown succeeds");
}

#[test]
fn connection_span_is_compatible_with_a_tracing_subscriber() {
    let observed_spans = Arc::new(AtomicUsize::new(0));
    let subscriber = Registry::default().with(CounterLayer(observed_spans.clone()));
    tracing::subscriber::with_default(subscriber, || {
        let _span = tracing::info_span!("websocket", transport = "axum");
    });
    assert_eq!(observed_spans.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn missing_credentials_are_rejected() {
    let server = SpikeServer::start().await.expect("server starts");
    let error = connect_async(format!("ws://{}/socket", server.address))
        .await
        .expect_err("authentication is mandatory");
    match error {
        Error::Http(response) => assert_eq!(response.status(), 401),
        other => panic!("server did not return an HTTP response: {other}"),
    }
    server.shutdown().await.unwrap();
}

#[tokio::test]
async fn slow_consumers_saturate_a_bounded_queue() {
    let server = SpikeServer::start().await.expect("server starts");
    let (mut socket, _) = connect_async(authenticated_request(server.address))
        .await
        .unwrap();
    for index in 0..256_u16 {
        if socket
            .send(Message::Binary(index.to_be_bytes().to_vec().into()))
            .await
            .is_err()
        {
            break;
        }
    }
    tokio::time::timeout(Duration::from_secs(2), async {
        while server.metrics.saturated_queues() == 0 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("bounded queue reports saturation");
    drop(socket);
    server.shutdown().await.unwrap();
}

struct CounterLayer(Arc<AtomicUsize>);

impl<S> tracing_subscriber::Layer<S> for CounterLayer
where
    S: tracing::Subscriber,
{
    fn on_new_span(
        &self,
        _attributes: &tracing::span::Attributes<'_>,
        _id: &tracing::span::Id,
        _context: tracing_subscriber::layer::Context<'_, S>,
    ) {
        self.0.fetch_add(1, Ordering::SeqCst);
    }
}

fn authenticated_request(address: std::net::SocketAddr) -> http::Request<()> {
    let mut request = format!("ws://{address}/socket")
        .into_client_request()
        .expect("spike URL is valid");
    request.headers_mut().insert(
        "authorization",
        HeaderValue::from_static(SPIKE_AUTHORIZATION),
    );
    request
}
