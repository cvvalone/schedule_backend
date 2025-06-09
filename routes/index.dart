import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  final html = '''
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Empty Route</title>
    <style>
      body {
        background: linear-gradient(135deg, #667eea, #764ba2);
        color: white;
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        display: flex;
        flex-direction: column;
        justify-content: center;
        align-items: center;
        height: 100vh;
        margin: 0;
        text-align: center;
      }
      h1 {
        font-size: 3rem;
        margin-bottom: 0.5rem;
        letter-spacing: 2px;
      }
      p {
        font-size: 1.2rem;
        opacity: 0.8;
      }
      .icon {
        font-size: 6rem;
        margin-bottom: 1rem;
        animation: pulse 2s infinite;
      }
      @keyframes pulse {
        0%, 100% { transform: scale(1); opacity: 1; }
        50% { transform: scale(1.1); opacity: 0.7; }
      }
    </style>
  </head>
  <body>
    <div class="icon">🚀</div>
    <h1>Welcome to the New Route!</h1>
    <p>This route is ready but has no content yet.</p>
    <p>Check back later or add some code here!</p>
  </body>
  </html>
  ''';

  return Response(body: html, headers: {'content-type': 'text/html; charset=utf-8'});
}
