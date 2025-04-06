async function fetchAndDisplayData(url: string): Promise<string> {
  const response = await fetch(url);
  const body = await response.text();

  // Function to escape HTML special characters
  function escapeHtml(text: string): string {
    const map: { [key: string]: string } = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    };
    return text.replace(/[&<>"']/g, function (m) { return map[m]; });
  }

  const escapedBody = escapeHtml(body);

  const html = `
    <h1>Data from: <a href="${url}">${url}</a></h1>
    <div style="border: 1px solid black; padding: 10px;">
      <div>${response.status} - ${response.statusText}</div>
      <iframe srcdoc="${escapedBody}"></iframe>
    </div>
  `;

  return html;
}

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const urls = [
      "https://www.binance.me/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo=1&pageSize=2&catalogId=161",
      "https://www.binance.com/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo=2&pageSize=2&catalogId=161",
      "https://www.binance.info/bapi/apex/v1/public/apex/cms/article/list/query?type=1&pageNo=2&pageSize=2&catalogId=161",
      "https://www.binance.com/en/support/announcement/list/161",
      "https://www.binance.info/en/support/announcement/list/93",
      "https://www.binance.me/en/support/announcement/list/93"
    ];

    let combinedHtml = "";
    for (const url of urls) {
      combinedHtml += await fetchAndDisplayData(url);
    }

    const workerIp = env.CF_IP || "Unknown IP";
    const workerName = env.CF_WORKER_NAME || "Unknown Worker";

    const fullHtml = `
      <html>
      <head>
      <title>Combined Binance Articles </title>
        </head>
        <body>
        <h1>Worker IP: ${workerIp}</h1>
        <h1>Worker Name: ${workerName}</h1>
        ${combinedHtml}
      </body>
      </html>
      `;

    return new Response(fullHtml, {
      headers: {
        'Content-Type': 'text/html;charset=UTF-8',
      },
    });
  },
} satisfies ExportedHandler<Env>;
