"""Minimal ASGI and WSGI apps for the server-side TLS tests."""


async def asgi(scope, receive, send):
    if scope["type"] != "http":
        return
    await send({"type": "http.response.start", "status": 200, "headers": [(b"content-type", b"text/plain")]})
    await send({"type": "http.response.body", "body": b"ok\n"})


def wsgi(environ, start_response):
    start_response("200 OK", [("Content-Type", "text/plain")])
    return [b"ok\n"]
