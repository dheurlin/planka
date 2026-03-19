import os
from http import server

class MyRequestHandler(server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        dir = os.path.dirname(os.path.realpath(__file__))
        super().__init__(*args, directory=dir, **kwargs)

    def end_headers(self) -> None:
        # Add the necessary headers to allow SharedArrayBuffer
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

if __name__ == "__main__":
    hej = server.HTTPServer(server_address=('', 8000), RequestHandlerClass=MyRequestHandler)
    hej.serve_forever()

