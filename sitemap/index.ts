import { CuckooFilter } from "bloom-filters";
import { appendFile, existsSync, mkdirSync } from 'fs';
import { writeFileSync, readFileSync } from 'fs';
import { join } from 'path';
import https from 'https';
import { XMLParser } from 'fast-xml-parser';
import { Chunk, Console, Effect, Stream } from "effect";

function appendToDateFile(text: string, directory: string = ".") {
  const date = new Date();
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const filename = `${year}-${month}-${day}.txt`;
  const filepath = join(directory, filename);

  if (!existsSync(directory)) {
    mkdirSync(directory, { recursive: true });
  }

  appendFile(filepath, text + '\n', (err) => {
    if (err) {
      console.error('Error appending to file:', err);
    } else {
      console.log(`Appended to ${filepath}`);
    }
  });
}

type State = {
  latestEtagForUrl: Record<string, string>,
  alreadySeenFilter: JSON
}

function saveState(state: State, filename: string = "state.json") {
  const serializedState = JSON.stringify(state);
  writeFileSync(filename, serializedState);
  console.log(`State saved to ${filename}`);
}

function loadState(filename: string = "state.json"): State | null {
  try {
    const serializedState = readFileSync(filename, 'utf-8');
    return JSON.parse(serializedState);
  } catch (error) {
    console.error(`Error loading state from ${filename}:`, error);
    return null;
  }
}

async function fetchWithEtag(url: string, etag: string | null = null): Promise<{ locs: string[], etag: string, url: string }> {
  return new Promise((resolve, reject) => {
    const options = {
      headers: {
        'If-None-Match': etag ? etag : ''
      }
    };

    https.get(url, options, (res) => {
      let data = '';

      if (res.statusCode === 304 && etag != null) {
        console.log('ETag matched, content not modified');
        resolve({ locs: [], etag: etag, url: url });
        return;
      }

      if (res.statusCode !== 200) {
        console.error(`Request failed with status code: ${res.statusCode}`);
        reject(new Error(`Request failed with status code: ${res.statusCode}`));
        return;
      }

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        const newEtag = res.headers.etag ? res.headers.etag : null;
        if (newEtag == null) {
          reject('No ETAG found');
        } else {
          const parser = new XMLParser();
          const xml = parser.parse(data);

          const urls = xml?.urlset?.url?.map((url: any) => url.loc) || [];
          resolve({ locs: urls, etag: newEtag, url: url });
        }
      });
    }).on('error', (err) => {
      console.error('Error during request:', err);
      reject(err);
    });
  });
}

let state = loadState()
let alreadySeenFilter: CuckooFilter = state && CuckooFilter.fromJSON(state.alreadySeenFilter) || new CuckooFilter(100000, 4, 10)
let latestEtag = state?.latestEtagForUrl || {}

let stream = Stream.range(0, 4).pipe(
  Stream.map(e => `https://www.binance.com/sitemap_output/domain=www.binance.com/sitemap_SupportAndAnnouncement_en_${e}.xml`),
  Stream.mapEffect((page) => Effect.promise(() => fetchWithEtag(page))),
  // Stream.rechunk(2),
  // Stream.filterMapEffect(c => {
  //   let a = Chunk.toReadonlyArray(c)
  //   let b = Effect.all(a)
  //   return b
  // }),
  Stream.tap(e => Console.log(e.url)),
  Stream.filter((element) => element.etag != (latestEtag[element.url] || "")),
  Stream.tap(e => Effect.succeed(latestEtag[e.url] = e.etag)),
  Stream.flatMap(e => Stream.fromIterable(e.locs)),
  Stream.filter(e => !alreadySeenFilter.has(e)),
  Stream.tap(e => {
    return alreadySeenFilter.add(e) && Effect.succeed({}) || Effect.fail("Filter is full")
  }),
)
let newLocs = Chunk.toReadonlyArray(await Effect.runPromise(Stream.runCollect(stream)))
console.log(`${newLocs.length} new URLs found`)
appendToDateFile(newLocs.join('\n'))


saveState({
  latestEtagForUrl: latestEtag,
  alreadySeenFilter: alreadySeenFilter.saveAsJSON()
})

