import { escapeHtml } from "./http.ts";

function shell(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)} — My Brief</title>
  <style>
    :root { color-scheme: light dark; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font: 16px/1.5 system-ui, -apple-system, Segoe UI, sans-serif;
      background: #f6f5f2;
      color: #1d1b18;
    }
    main {
      max-width: 32rem;
      margin: 1.5rem;
      padding: 2rem;
      border-radius: 1rem;
      background: #fff;
      box-shadow: 0 8px 30px rgba(0, 0, 0, .08);
    }
    h1 { margin: 0 0 .5rem; font-size: 1.4rem; }
    p { margin: .5rem 0 0; color: #5d5952; }
    @media (prefers-color-scheme: dark) {
      body { background: #171614; color: #f2efe9; }
      main { background: #211f1c; box-shadow: none; }
      p { color: #b9b3a8; }
    }
  </style>
</head>
<body>
  <main>
    ${body}
  </main>
</body>
</html>`;
}

export function successPage(email: string): string {
  return shell(
    "Connected",
    `<h1>Mailbox connected</h1>
     <p>${escapeHtml(email)} is now syncing with My Brief.</p>
     <p>You can close this tab and return to the app. New mail should appear within a few minutes.</p>`,
  );
}

export function errorPage(message: string): string {
  return shell(
    "Connection failed",
    `<h1>Connection failed</h1>
     <p>${escapeHtml(message)}</p>
     <p>You can close this tab and try again from Settings in My Brief.</p>`,
  );
}
