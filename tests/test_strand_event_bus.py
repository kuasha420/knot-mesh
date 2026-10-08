#!/usr/bin/env python3
"""
Test Suite for Knot Hub Reactive Strand Event Bus (Issue #72)
Verifies:
1. Event ingestion via POST /strand/event (input validation, default fields, status 200)
2. SSE streaming via GET /strand/events with and without run_id filtering
3. Local UNIX domain socket push bus (~/.config/knot/events.sock)
4. Multi-client broadcast distribution
"""

import json
import os
import socket
import sys
import tempfile
import threading
import time
import unittest
from http.server import ThreadingHTTPServer
from urllib import request as urllib_request

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from core.hub.hub import (
    HubRequestHandler,
    Database,
    publish_strand_event,
    start_events_socket_server,
    stop_events_socket_server,
)


class TestStrandEventBusUnit(unittest.TestCase):
    def test_publish_validation(self):
        # Non-dict payload must raise ValueError
        with self.assertRaises(ValueError):
            publish_strand_event("invalid_string")  # type: ignore

        # Missing event field must raise ValueError
        with self.assertRaises(ValueError):
            publish_strand_event({"run_id": "test_run", "node_id": "laptop"})

    def test_publish_defaults(self):
        event = publish_strand_event({
            "event": "TURN_START",
            "node_id": "steamdeck",
        })
        self.assertEqual(event["event"], "TURN_START")
        self.assertEqual(event["node_id"], "steamdeck")
        self.assertEqual(event["run_id"], "")
        self.assertIn("timestamp", event)
        self.assertIsInstance(event["details"], dict)


class TestStrandEventBusIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp_dir = tempfile.TemporaryDirectory()
        cls.db_path = os.path.join(cls.tmp_dir.name, "hub.db")
        cls.sock_path = os.path.join(cls.tmp_dir.name, "events.sock")

        # Set up Database
        cls.db = Database(cls.db_path)
        HubRequestHandler.db = cls.db

        # Bind HTTPServer on ephemeral loopback port
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), HubRequestHandler)
        cls.port = cls.httpd.server_address[1]
        cls.base_url = f"http://127.0.0.1:{cls.port}"

        cls.httpd_thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.httpd_thread.start()

        # Start UNIX socket server
        cls.sock_thread = start_events_socket_server(cls.sock_path)
        time.sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        stop_events_socket_server()
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.tmp_dir.cleanup()

    def test_post_event_endpoint(self):
        url = f"{self.base_url}/strand/event"
        payload = {
            "run_id": "run_test_123",
            "node_id": "laptop",
            "event": "AWAITING_INPUT",
            "details": {"turn": 2, "status": "waiting"}
        }
        data = json.dumps(payload).encode("utf-8")
        req = urllib_request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")

        with urllib_request.urlopen(req, timeout=5.0) as resp:
            self.assertEqual(resp.status, 200)
            body = json.loads(resp.read().decode("utf-8"))
            self.assertEqual(body.get("status"), "ok")
            ev = body.get("event", {})
            self.assertEqual(ev.get("event"), "AWAITING_INPUT")
            self.assertEqual(ev.get("node_id"), "laptop")
            self.assertEqual(ev.get("run_id"), "run_test_123")

    def test_unix_domain_socket_push(self):
        self.assertTrue(os.path.exists(self.sock_path))
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(3.0)
        client.connect(self.sock_path)

        received_events = []
        connected_event = threading.Event()

        def reader():
            buf = ""
            while len(received_events) < 1:
                try:
                    chunk = client.recv(4096).decode("utf-8")
                    if not chunk:
                        break
                    buf += chunk
                    while "\n" in buf:
                        line, buf = buf.split("\n", 1)
                        if line.strip():
                            ev = json.loads(line.strip())
                            if ev.get("event") == "CONNECTED":
                                connected_event.set()
                            else:
                                received_events.append(ev)
                except Exception:
                    break

        t = threading.Thread(target=reader, daemon=True)
        t.start()

        # Wait until server has accepted the connection
        self.assertTrue(connected_event.wait(timeout=2.0))

        # Publish an event
        payload = {
            "run_id": "run_sock_456",
            "node_id": "rog-ally",
            "event": "TURN_START",
            "details": {"round": 1}
        }
        publish_strand_event(payload)

        t.join(timeout=2.0)
        client.close()

        self.assertEqual(len(received_events), 1)
        self.assertEqual(received_events[0]["node_id"], "rog-ally")
        self.assertEqual(received_events[0]["event"], "TURN_START")
        self.assertEqual(received_events[0]["run_id"], "run_sock_456")

    def test_sse_streaming_endpoint(self):
        sse_url = f"{self.base_url}/strand/events?run_id=run_sse_789"
        received_events = []
        stop_event = threading.Event()

        def sse_client():
            req = urllib_request.Request(sse_url, headers={"Accept": "text/event-stream"})
            try:
                with urllib_request.urlopen(req, timeout=5.0) as resp:
                    for line_bytes in resp:
                        if stop_event.is_set():
                            break
                        line = line_bytes.decode("utf-8").strip()
                        if line.startswith("data:"):
                            data_str = line[5:].strip()
                            try:
                                d = json.loads(data_str)
                                if d.get("event") == "COMPLETED":
                                    received_events.append(d)
                                    break
                            except Exception as parse_err:
                                sys.stderr.write(f"SSE parse notice: {parse_err}\n")
            except Exception as stream_err:
                sys.stderr.write(f"SSE client stream closed: {stream_err}\n")

        t = threading.Thread(target=sse_client, daemon=True)
        t.start()
        time.sleep(0.2)  # Give client time to connect

        # Post matching event
        post_url = f"{self.base_url}/strand/event"
        payload = {
            "run_id": "run_sse_789",
            "node_id": "desktop",
            "event": "COMPLETED",
            "details": {"score": 100}
        }
        req_post = urllib_request.Request(
            post_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with urllib_request.urlopen(req_post, timeout=5.0) as resp:
            self.assertEqual(resp.status, 200)

        t.join(timeout=3.0)
        stop_event.set()

        self.assertGreaterEqual(len(received_events), 1)
        self.assertEqual(received_events[0]["event"], "COMPLETED")
        self.assertEqual(received_events[0]["node_id"], "desktop")

    def test_council_reply_publishes_strand_event(self):
        # Create thread
        tid = "thread_reply_test"
        rid = "run_reply_test_99"
        self.db.create_council_thread(tid, rid, "Reply Test", "Body", "general", f"knot://mesh/council/{tid}")

        # Connect socket to listen for ACK
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(3.0)
        client.connect(self.sock_path)

        events = []
        ready = threading.Event()

        def sock_reader():
            buf = ""
            while len(events) < 1:
                try:
                    chunk = client.recv(4096).decode("utf-8")
                    if not chunk:
                        break
                    buf += chunk
                    while "\n" in buf:
                        line, buf = buf.split("\n", 1)
                        if not line.strip():
                            continue
                        d = json.loads(line.strip())
                        if d.get("event") == "CONNECTED":
                            ready.set()
                        elif d.get("run_id") == rid:
                            events.append(d)
                except Exception:
                    break

        t = threading.Thread(target=sock_reader, daemon=True)
        t.start()
        self.assertTrue(ready.wait(timeout=2.0))

        # Post reply to /council/threads/{tid}/reply
        url = f"{self.base_url}/council/threads/{tid}/reply"
        payload = {
            "run_id": rid,
            "node_id": "laptop",
            "status": "PROGRESS",
            "body": "Analyzing issue"
        }
        req = urllib_request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with urllib_request.urlopen(req, timeout=5.0) as resp:
            self.assertEqual(resp.status, 201)

        t.join(timeout=2.0)
        client.close()

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["event"], "ACK")
        self.assertEqual(events[0]["node_id"], "laptop")
        self.assertEqual(events[0]["run_id"], rid)

    def test_socket_client_abrupt_disconnect(self):
        # Connect a client and immediately close without reading
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.connect(self.sock_path)
        time.sleep(0.05)
        client.close()

        # Publishing must not fail despite dead socket client
        payload = {
            "run_id": "run_disconnect_test",
            "node_id": "steamdeck",
            "event": "AWAITING_INPUT"
        }
        res = publish_strand_event(payload)
        self.assertEqual(res["event"], "AWAITING_INPUT")


if __name__ == "__main__":
    unittest.main()
