async function fetchAndDisplayData(url: string): Promise<string> {
  const response = await fetch(url);

  if (!response.ok) {
    return `
      <h1>Error fetching data from: <a href="${url}">${url}</a></h1>
      <div style="border: 1px solid black; padding: 10px; color: red;">
        Error: ${response.status} - ${response.statusText}
      </div>
    `;
  }

  const jsonData = await response.json();

  const html = `
    <h1>Data from: <a href="${url}">${url}</a></h1>
    <div style="border: 1px solid black; padding: 10px;">
      <pre>` + JSON.stringify(jsonData, null, 2) + `</pre>
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
