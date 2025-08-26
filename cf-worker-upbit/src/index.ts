async function fetchAndDisplayData(url: string, etag?: string): Promise<Response> {
  const headers: Record<string, string> = {};
  if (etag) headers['If-None-Match'] = etag;
  const response = await fetch(url, { headers });
  return response;
}

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const { searchParams } = new URL(request.url);

    const os = searchParams.get('os') || 'web';
    const page = searchParams.get('page') || '1';
    const per_page = searchParams.get('per_page') || '20';
    const category = searchParams.get('category') || 'all';
    const etag = searchParams.get('etag') || null;
    const total_count = Number.parseInt(searchParams.get('total') || '0');
    const seed = Number.parseInt(searchParams.get('seed') || '0');

    let url = `https://api-manager.upbit.com/api/v1/announcements?os=${encodeURIComponent(os)}&page=${encodeURIComponent(page)}&per_page=${encodeURIComponent(per_page)}&category=${encodeURIComponent(category)}&seed=${seed}`

    const upstream = await fetchAndDisplayData(url, etag ?? undefined);
    const body = await upstream.text();

    if (upstream.status === 304 || upstream.status > 400) {
      return new Response(body, { status: upstream.status });
    }
    if (body.startsWith('error code')) {
      return new Response(body, { status: 429 });
    }

    if (total_count > 1 && body.slice(25, 100).indexOf(`"total_count":${total_count + 1}`) < 0) {
      return new Response(null, { status: 304 });
    }
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    const upstreamEtag = upstream.headers.get('ETag') || upstream.headers.get('etag');
    if (upstreamEtag) headers['etag'] = upstreamEtag;

    return new Response(body, { headers });
  },
} satisfies ExportedHandler<Env>;
