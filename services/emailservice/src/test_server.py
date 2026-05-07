import unittest

from server import build_response


class EmailServiceTests(unittest.TestCase):
    def test_health_endpoint(self):
        status, payload = build_response("GET", "/health")
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "ok")

    def test_ready_endpoint(self):
        status, payload = build_response("GET", "/ready")
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "ready")

    def test_send_endpoint_accepts_mock_email(self):
        status, payload = build_response("GET", "/send", "to=user@example.com&order=abc123")
        self.assertEqual(status, 200)
        self.assertEqual(payload["recipient"], "user@example.com")
        self.assertEqual(payload["orderId"], "abc123")


if __name__ == "__main__":
    unittest.main()
