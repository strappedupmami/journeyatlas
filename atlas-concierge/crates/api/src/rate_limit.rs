use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::time::{Duration, Instant};

use parking_lot::Mutex;

#[derive(Debug, Clone)]
pub struct IpRateLimiter {
    inner: Arc<Mutex<HashMap<String, VecDeque<Instant>>>>,
    window: Duration,
    max_requests: usize,
}

impl IpRateLimiter {
    pub fn new(window: Duration, max_requests: usize) -> Self {
        Self {
            inner: Arc::new(Mutex::new(HashMap::new())),
            window,
            max_requests,
        }
    }

    pub fn allow(&self, key: &str) -> bool {
        let now = Instant::now();
        let mut guard = self.inner.lock();
        let queue = guard.entry(key.to_string()).or_default();

        while let Some(front) = queue.front() {
            if now.duration_since(*front) > self.window {
                queue.pop_front();
            } else {
                break;
            }
        }

        if queue.len() >= self.max_requests {
            return false;
        }

        queue.push_back(now);
        true
    }
}
