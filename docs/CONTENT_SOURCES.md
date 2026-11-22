# Content sources: the catalogue

Every place the content pipeline (`docs/CONTENT_PIPELINE.md`) may take material from, with its address, its license and what was checked. The design of the `feeds` and `scout` stages is in that document; this file is the list they read from.

**How to read the "Checked" column**
- Ticket 06 rechecked the implemented sources on 2026-11-16; the dated notes below supersede older network and plan observations.
- **answered**: the address was called from this PC and returned data; the dated ticket 06 notes below record the 2026-11-16 rechecks.
- **terms read**: the license or terms page was opened and read on 2026-11-11 or 2026-11-12.
- **not checked**: from memory or from a search result only. The ticket that builds the reader checks it first and corrects this file.
- **no answer**: the address did not answer from this PC's network on 2026-11-12. The ticket retries; it may be this network.

Rules for every reader
- Send a `User-Agent` that names the project and a contact address (`SmartScrollingPipeline/1.0 (<CONTACT_EMAIL>)`). Wikimedia and Open Library ask for this; with it Open Library allows 3 requests a second, without it 1.
- At most one request a second to any site, and one every 3 seconds to arXiv.
- A reader that gets an error stops for this run. It never retries in a loop.
- A license that is not in the "used" rows of the license rule (`CONTENT_PIPELINE.md` section 8) means the item is skipped.

"First" in the tables marks the readers pipeline ticket 06 builds. The others are added when wanted.

## 1. News

A news card is written in the pipeline's own words from the facts, names the publisher and links to the original.

| Source | First | Address | Text you get | License | Checked |
|---|---|---|---|---|---|
| Wikipedia, Current events | yes | `https://en.wikipedia.org/w/api.php?action=parse&page=Portal:Current_events/<yyyy>_<Month>_<d>&prop=wikitext&format=json&formatversion=2` | one page per day: short items grouped by subject, each with links to the Wikipedia articles and to the press | CC BY-SA 4.0 | answered |
| Wikipedia, "In the news" | yes | `https://api.wikimedia.org/feed/v1/wikipedia/en/featured/<yyyy>/<mm>/<dd>` (field `news`: `story` plus `links`; also `tfa` = the featured article and `mostread`) | a few top stories a day with the linked articles' summaries | CC BY-SA 4.0 | answered |
| NASA news releases | yes | `https://www.nasa.gov/news-release/feed/` (RSS with the full text) | full release | US government work: public domain, except other people's pictures and logos | answered; terms from a search result |
| European Commission press corner | yes | `https://ec.europa.eu/commission/presscorner/api/rss?language=en` (RSS; each item links to the full release) | title and link; the release page has the full text | CC BY 4.0 for the Commission's own content | answered; terms read |
| Voice of America | no | RSS per section, listed at `https://www.voanews.com/rssfeeds` | summary and link | US government work; some items come from news agencies and are not free (skip items credited to AP, Reuters, AFP) | answered; terms not checked |
| Global Voices | no | `https://globalvoices.org/feed/` | full text | CC BY 3.0 | answered; terms not checked |
| Other US agencies (NIH, NSF, NOAA, CDC) | no | each has a news RSS feed | full release | public domain | not checked |
| CERN, ESA, UN News, WHO | no | news RSS feeds | varies | CERN: CC BY; the others have their own terms | not checked |

For a Wikipedia news item the reader takes the day's item and the lead section of the first linked article as the text, so the model has enough facts. `newspaper` is "Wikipedia Current events" and `link` is the linked article.

**News services with a free key.** They return the headline, a short description (one to three sentences), the publisher and the link. The full article is in their paid plans. One short card is written from the headline and description only; an item with fewer than 40 words of them is skipped. Their plans were read on their own pages on 2026-11-12; none was called, because calling needs a key.

| Service | First | Free plan | Conditions | Address (check with the key) | Checked |
|---|---|---|---|---|---|
| NewsData.io | yes | 200 calls a day, up to 10 articles a call, delayed headlines/descriptions | personal/internal API use; publisher rights stay separate; keep attribution and summarize facts only | `https://newsdata.io/api/1/latest?apikey=<key>&language=en&category=<category>` | answered; terms read 2026-11-16 |
| Currents | yes | free key returns headlines/descriptions | included under explicit authorization obtained by the owner; `Currents authorized use` label, not CC | `https://api.currentsapi.services/v1/latest-news?language=en&category=technology`, bearer header | answered; reader restored 2026-11-16 |
| GNews | no | 100 calls a day, up to 10 articles a call, 12 hours late, text cut to 250 characters | non-commercial use only | `https://gnews.io/api/v4/top-headlines?apikey=<key>&lang=en` | not checked |
| TheNewsAPI | no | 100 calls a day, 3 articles a call | terms not read | | not checked |
| World News API | no | 50 points a day | a link back to them is required | | not checked |
| mediastack | no | 100 calls a month, delayed | non-commercial use only; too small to be useful | | not checked |
| Webz.io | no | 5 dollars of free credit a month, no card needed | what that credit buys, and its terms, could not be read from its pages | | not checked |

A reader for one of these maps the service's categories to topic ids in its feed line, for example `{"reader": "newsdata", "params": {"category": "science"}, "topics": ["physics"], "per_day": 3}`. `newspaper` is the publisher's name as the service gives it, `link` is the article. For NewsData.io the source `description` ends with "News data by NewsData.io."

**Not usable, with the reason**

| Source | Why not | Checked |
|---|---|---|
| The Guardian Open Platform | its terms forbid using the content with machine learning or AI to generate content, forbid text mining, and require deleting everything after 24 hours | terms read |
| NewsAPI.org free plan | allowed for development and testing only; any real use is forbidden | terms read |
| New York Times APIs | non-commercial only, and its terms bar using the content with generative AI without written consent | search result |
| ANSA | no reuse without a contract; automated collection and AI use forbidden | search result |
| The Conversation, ProPublica, Mongabay | "no derivatives" licenses (CC BY-ND, CC BY-NC-ND): a card is a new work made from the text | search result |
| Wikinews | closed in 2026; its last article is from May 2026 | answered |
| NewsAPI.ai / Event Registry, newscatcher, Perigon | not looked at | not checked |
| GDELT, Hacker News | they answer, but give only links and titles; there is no text the pipeline may summarise | answered |

Full newspaper articles are not free anywhere. The open sources at the top give full text; the services with a free key give a headline and a short description, which is enough for one short card.

## 2. Books to read (the wish list, stage `scout`)

| Source | First | Address | Gives | Key | Checked |
|---|---|---|---|---|---|
| Open Library search | yes | `https://openlibrary.org/search.json?title=<t>&author=<a>&fields=key,title,author_name,first_publish_year,isbn,subject,language,readinglog_count,ratings_average&limit=5` | proof that a book exists, its work key, year, ISBNs, subjects, how many people shelved it | none | answered |
| Open Library trending | yes | `https://openlibrary.org/trending/monthly.json?limit=50` | what is being read now (mixed fiction and non-fiction: the scout's filter removes fiction) | none | answered |
| Open Library subjects | yes | `https://openlibrary.org/subjects/<subject>.json?limit=50` | well-known works of a subject | none | answered |
| Open Library covers | yes | `https://covers.openlibrary.org/b/isbn/<isbn>-L.jpg` | the cover picture | none | answered |
| Prize winners | yes | the prize's list page on Wikipedia: `https://en.wikipedia.org/w/api.php?action=parse&page=<prize page>&prop=wikitext&format=json&formatversion=2`, read for book titles and authors | books that won a prize | none | answered for all four prize pages on 2026-11-16 (wikitable rows with author + italic title). Wikidata was tried and is not the way: its "award received" query for the Pulitzer returns the authors (people), not the books |
| New York Times best-seller lists | no | `https://api.nytimes.com/svc/books/v3/lists/current/hardcover-nonfiction.json?api-key=<key>` | this week's best-sellers | free key | not checked |
| Model suggestions | yes | role `scout` | titles for thin topics; each must then exist on Open Library | none | n/a |

Prize pages to read: "Pulitzer Prize for General Nonfiction", "National Book Award for Nonfiction", "Baillie Gifford Prize", "Royal Society Science Book Prize". Every title read from a page still has to pass the Open Library check before it enters the wish list.

Not usable: Goodreads (no public interface), ISBNdb (paid).

## 3. Free books

| Source | First | Address | License | Checked |
|---|---|---|---|---|
| Project Gutenberg | yes | through the official mirror `https://gutenberg.pglaf.org`: catalogue `/cache/epub/feeds/pg_catalog.csv` (download weekly, search locally); a book `/cache/epub/<id>/pg<id>-images-3.epub` or `/cache/epub/<id>/pg<id>.txt` | public domain in the US; remove the Gutenberg header and footer from the text | the mirror answered for all three. The main site `www.gutenberg.org` did not answer from this network, and its robot rules (terms read) send programs to the mirrors anyway. One file at a time, 2 seconds apart |
| Standard Ebooks | no | new releases `https://standardebooks.org/feeds/rss/new-releases`; each book page has a direct EPUB link | CC0 | answered; terms read. Their full catalogue feeds are for paying patrons, and the site blocks crawlers that follow a hidden link, so take only links found in the feed |
| Wikisource | no | MediaWiki API, plain text | public domain or CC BY-SA | not checked |

Pipeline ticket 03 check, 2026-11-12: the PGLAF HTTPS mirror now fails with an expired certificate; HTTP redirects to it. The main Gutenberg host timed out. The official [mirror list](https://www.gutenberg.org/MIRRORS.ALL) also lists `https://mirror.cs.odu.edu/gutenberg-epub/`: its `feeds/pg_catalog.csv` and EPUBs `16287/pg16287-images-3.epub` (William James) and `14474/pg14474-images-3.epub` (Michael Faraday) answered with TLS verification enabled. These files stay in the temporary ticket 03 home, outside git.

## 4. Papers

| Source | First | Address | Text you get | License | Checked |
|---|---|---|---|---|---|
| arXiv | yes | `https://export.arxiv.org/api/query?search_query=cat:<category>&sortBy=submittedDate&sortOrder=descending&max_results=10` | title, authors, abstract | the metadata, with the abstract, is CC0; the paper itself is not free to copy: link to `arxiv.org/abs/<id>` | answered; terms read (one request every 3 seconds, one connection) |
| Hugging Face daily papers | yes | `https://huggingface.co/api/daily_papers?limit=20` | a daily list of notable AI papers with their arXiv ids | used only to choose which arXiv papers to take | answered; terms not checked |
| Europe PMC, open-access part | yes | search `https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=<q>%20AND%20OPEN_ACCESS:y&format=json&resultType=core&pageSize=10` (fields `abstractText`, `license`, `doi`, `journalTitle`, `pmcid`); full text `https://www.ebi.ac.uk/europepmc/webservices/rest/<pmcid>/fullTextXML` | abstract; full text for the open part | per paper, in the `license` field: keep `cc0`, `cc by`, `cc by-sa` | both answered |
| OpenAlex | no | `https://api.openalex.org/works?…` | metadata, open-access place, license, citations | data is CC0. Needs a free key since February 2026 | terms read |
| Semantic Scholar, Crossref, CORE, bioRxiv | no | | | | not checked |

A paper becomes a `paper` source: `paper.doi`, `paper.journal`, `paper_status` (`preprint` for arXiv and bioRxiv).

## 5. Articles and reference texts

| Source | First | Address | License | Checked |
|---|---|---|---|---|
| Wikipedia article | yes | `https://en.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=1&format=json&formatversion=2&titles=<title>` | CC BY-SA 4.0 | answered |
| Wikipedia vital articles | yes | the list pages under `Wikipedia:Vital_articles` (level 3 is about 1,000 topics) | used as the wish list of topics | answered 2026-11-16; namespace-zero links, skipping seen titles |
| Our World in Data | no | new articles `https://ourworldindata.org/atom.xml` | CC BY | answered; terms not checked |
| OpenStax textbooks | no | PDF per book from openstax.org, dropped into the inbox folder | most are CC BY-NC-SA, a few CC BY: read each book's page | search result |
| MIT OpenCourseWare | no | PDFs, dropped into the inbox folder | CC BY-NC-SA | not checked |
| Stanford Encyclopedia of Philosophy | | | not open: do not use | not checked |

## 6. Pictures

| Source | First | Address | License | Checked |
|---|---|---|---|---|
| The Met | yes | search `https://collectionapi.metmuseum.org/public/collection/v1.1/search?hasImages=true&isPublicDomain=true&q=<q>`; one work `https://collectionapi.metmuseum.org/public/collection/v1/objects/<id>` (`primaryImage`, `title`, `artistDisplayName`, `objectDate`, `medium`, `isPublicDomain`) | CC0 when the work's own `isPublicDomain` is true. Check it on the work: the first search result was not public domain although the search asked for it | both answered |
| Wikimedia Commons | yes | `https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=<q>&gsrnamespace=6&prop=imageinfo&iiprop=url|extmetadata&iiextmetadatafilter=LicenseShortName|Artist|ImageDescription&format=json` | per file, in `LicenseShortName`: keep public domain, CC0, CC BY, CC BY-SA; the credit names the `Artist` | answered |
| NASA picture of the day | no | `https://api.nasa.gov/planetary/apod?api_key=<key>&date=<yyyy-mm-dd>` | public domain unless the item has a `copyright` field (skip those) | the shared `DEMO_KEY` returned an error; get your own free key |
| Art Institute of Chicago | no | `https://api.artic.edu/api/v1/artworks/search?q=<q>&limit=10&fields=id,title,image_id,is_public_domain,artist_title`; picture `https://www.artic.edu/iiif/2/<image_id>/full/843,/0/default.jpg` | CC0 when `is_public_domain` is true | answered, with a browser-like `User-Agent` plus an `AIC-User-Agent` header |
| Smithsonian, Rijksmuseum, Europeana, Openverse | no | | CC0 filters exist; each needs a free key | not checked |

A picture is downloaded once, checked to be a JPEG, PNG or WebP under 50 MB by its first bytes, and stored through `upload.py` as the card's `media`.

Audio and video cards are not made by the pipeline in this version. LibriVox (public-domain audiobooks) and NASA's video library are the places to start when they are wanted.

## Ticket 06 verification, 2026-11-16

- **NewsData.io: answered; terms read** at `https://newsdata.io/terms`. The keyed latest endpoint returned `article_id`, `title`, `description`, `creator`, `pubDate`, `link`, `source_name`, and `source_id`; `content` says `ONLY AVAILABLE IN PAID PLANS`. The first five descriptions were 446, 370, 167, 286, and 286 characters. The API license permits personal/internal use, while third-party rights remain with their owners and the service grants no independent rights to raw publisher text. The reader therefore supplies only headline/description for the design's personal factual-summary use, labels it `NewsData.io personal/internal use` (never a Creative Commons license), and retains the publisher, original link, requested NewsData hyperlink, and `News data by NewsData.io.` credit. It skips fewer than 40 words; this is not authorization to republish publisher wording.
- **Currents: answered; reader restored with owner authorization.** The owner obtained explicit authorization for this use, with no commercialization or further production. The earlier exclusion is superseded for that scope; the label `Currents authorized use` records it without asserting a general Creative Commons license grant. The keyed endpoint returned `id`, `title`, `description`, `url`, `author`, `image`, `language`, `category`, `source_category`, and `published`; the initial five descriptions were 251, 149, 261, 209, and 197 characters. A fresh call with a bearer header returned 20 items; two short answers are saved in `testdata/readers/currents.json`. Publisher attribution comes from the article URL hostname because `author` names a journalist. The reader keeps headline/description facts, original link and Currents credit, and skips fewer than 40 words. The service's technology category also included entertainment/weather stories, so it is not proof of the final topic. The [API documentation](https://currentsapi.services/en/docs/) and [terms](https://currentsapi.services/terms) remain the references; local/noncommercial intent does not change their text.
- **Wikipedia Current events, daily news, article, vital list, NASA, Commons: answered.** Python's default trust chain initially reported expired certificates; Git's CA bundle was used for the original proof with verification enabled. The cause was subsequently identified as one expired cross-signed ISRG Root X2 intermediate in the Windows user cache, backed up and removed on 2026-11-16 (details in `CONTENT_PIPELINE.md`). Fresh Wikipedia, NASA, Commons and Currents requests now verify with Python's default trust store and no `SSL_CERT_FILE`; expired, self-signed and wrong-host test certificates are refused. The daily featured feed must use today's date: yesterday's response lacked `news`, whereas today's contained it. Current events still uses yesterday. The vital list uses `prop=links` and namespace-zero titles, then skips previously seen article keys.
- **European Commission: answered.** RSS descriptions are truncated. Full HTML is returned by `https://ec.europa.eu/commission/presscorner/api/documents?reference=IP%2F26%2F2440&language=en`, under `docuLanguageResource.htmlContent`; convert the RSS identifier's underscores to slashes and uppercase it. A live reader returned the full 12,727-character speech, not its RSS excerpt.
- **arXiv, Hugging Face, Europe PMC: answered.** arXiv's Atom fields and HF's `paper.id` matched the contract. A live PMC search gave `license: cc by`; its JATS `body` supplied full text. The reader never downloads full text for an unknown or refused license. Live arXiv/HF abstracts contained 1,363/1,425 characters, and PMC body 30,973 characters.
- **Gutenberg ODU mirror: answered.** The catalogue is now 21,290,329 bytes, so it has a separate 30 MB download bound (the normal text request bound stays 5 MB), cached atomically for seven days. The reader fetched public-domain Faraday EPUB 14474 into a temporary home, with TLS verification enabled; book bytes and full text stay out of git.
- **Met: answered.** Search `/public/collection/v1/search` now returns HTTP 410; `/public/collection/v1.1/search` answers. Object reads still use `/v1/objects/<id>`. Object 436524 reported `isPublicDomain: true` and its JPEG downloaded successfully; the reader rechecks the work's own flag before downloading.
- **News category quality:** NewsData's own `science` category included basketball scores. The reader rejects rows that do not include the requested category, but the service's classification can itself be wrong; its category is not proof that the item's facts fit the mapped topic.
- **Europe PMC links:** article lookup uses `query=PMCID:PMC7619672` (one observed result). `EXT_ID:PMC7619672` and `PMC:PMC7619672` returned zero. Feed queries always include `AND OPEN_ACCESS:y`; open access alone still does not establish an allowed license.
- **Repeat discovery:** Gutenberg subject queries and Met/Commons searches skip recorded item keys before fetching files. Commons follows search continuation when an earlier page is exhausted; explicit manual identifiers remain readable. Gutenberg additionally checks the EPUB's own OPF `dc:rights` begins with public domain before labeling it public domain. The fixture EPUB contains that metadata only, no book contents.

## 7. Where the model providers are

| Provider | Address | Notes | Checked |
|---|---|---|---|
| Claude subscription | the `claude` program | preset in `CONTENT_PIPELINE.md` 9.3 | tested on this PC |
| ChatGPT subscription | the `codex` program | preset in 9.3 | tested on this PC |
| Google AI Pro subscription | the `agy` program (Antigravity CLI) at `%USERPROFILE%\.gemini\bin\agy.exe` | preset and limits in 9.3: the prompt must be on the command line, and its tools cannot be switched off | tested on this PC |
| Gemini API key | `https://generativelanguage.googleapis.com/v1beta/openai` | free key at aistudio.google.com; small daily limits that differ per model; the free allowance may use your text to improve Google's products | not checked |
| OpenRouter | `https://openrouter.ai/api/v1` | free models: 20 calls a minute, 50 a day, or 1,000 a day once 10 credits were ever bought | terms read |
| Ollama (local) | `http://localhost:11434/v1` | set `OLLAMA_CONTEXT_LENGTH` to at least 16000 before starting it; the default on a normal graphics card is about 4,000 tokens | terms read |
| LM Studio (local) | `http://localhost:1234/v1` | | not checked |
| llama.cpp server (local) | `http://localhost:8080/v1` | start with `-c 16384` | not checked |
| Groq, Mistral, DeepSeek, Together | their OpenAI-style addresses | free allowances and JSON support differ; DeepSeek only forces "some JSON" (`"json": "object"`) | not checked |

Model names change every few months, so none is written here. A provider's `model` is set in the settings, and the exam (`CONTENT_PIPELINE.md` 9.5) decides whether it may be used.

## 8. Existing source round-trip checks

Pipeline ticket 08, 2026-11-16: rebuilt `happiness-advantage` and `incepholorgb` into temporary folders and ran `no_change` read-only. Both returned true: no source, card, test, detail, topic or link differences; existing storage references were retained without downloading cover/card media. Nothing was uploaded to either real source. Private source text stayed outside git. The separate public-domain trial and its three test requests were removed; the database returned to its previously documented two-real-source, zero-sample baseline. The local app sample box was untouched.
