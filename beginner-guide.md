# idempotent-file-ledger — explained for beginners

## The big goal, in one sentence

We're building a system where you can upload the same file a hundred times
by accident and it only ever gets **processed once** — the system remembers
what it's already seen and skips duplicates automatically.

## Why does that matter?

Imagine a folder where files get dropped in from all over — customer
uploads, an automated export job, a flaky script that retries on failure.
Two problems show up constantly in real systems like this:

- **The same file gets uploaded twice** (a user double-clicks "upload", a
  retry fires after a timeout even though the first attempt actually
  succeeded). Without protection, you'd process it twice — maybe charging
  someone twice, or sending a duplicate report.
- **A file fails halfway through processing** and needs to be retried, but
  you want to *know* it's a retry, not silently pretend it's brand new.

"Idempotent" is just a fancy word for **"doing it twice has the same effect
as doing it once."** That's the whole point of this project: no matter how
many times a file shows up, the outcome is correct and nothing gets
double-counted.

## The plan, at a high level

```
  Someone uploads      A program notices     It checks: "have I
  a file to a           the new file and       seen THIS file's
  storage bucket   -->  wakes up automatically -->  content before?"  --> record the outcome
```

We're using Amazon Web Services (AWS) building blocks to do this — but
instead of paying real AWS money while we build and test, we run everything
against a **local fake AWS** on our own laptop. More on that below.

## Key terms (plain-English glossary)

| Term | What it actually means here |
|---|---|
| **Terraform** | A tool that lets you describe infrastructure ("I want a storage bucket named X") as text files, instead of clicking around in a web console. Run it, and it creates (or updates, or deletes) exactly what the text describes. |
| **MiniStack** | A program that pretends to be AWS, running on `localhost:4566` on this machine. It understands the same commands real AWS does, so we can build and test everything for free, with no internet, before ever touching a real AWS account. |
| **S3 bucket** | AWS's file storage service ("Simple Storage Service"). Think of it like a folder in the cloud you can upload files into. Ours is called `file-ledger-landing`. |
| **DynamoDB** | AWS's database service. We use it to keep one row per unique file — its "fingerprint," when we first saw it, and its status. Ours is called `file-ledger`. |
| **Lambda function** | A small piece of code that AWS runs *for you* automatically, in response to an event — you don't manage a server, it just runs when triggered. Ours wakes up every time a file lands in the S3 bucket. |
| **IAM role** | A set of permissions. Our Lambda function has a role that says "you're allowed to read from the landing bucket and read/write the ledger table — nothing else." This limits the blast radius if anything goes wrong. |
| **SHA-256 hash** | A short (64-character) fingerprint calculated from a file's content. The magic property: the *exact same content* always produces the *exact same fingerprint*, and even a one-character change produces a totally different one. This is how we detect "is this the same file I saw before?" without comparing entire files byte-by-byte. |
| **pytest** | A tool for writing small, automated checks ("tests") that prove a piece of code behaves correctly, without needing to run the whole system. |

## Day 1 — laying the foundation

**Goal:** get Terraform talking to MiniStack instead of real AWS, and create
the two pieces of infrastructure everything else depends on.

What we built:

1. **`provider.tf`** — told Terraform "when you create AWS things, send
   those requests to `http://localhost:4566` (MiniStack), not real AWS."
   Since it's not real AWS, we used fake credentials (`test` / `test`) —
   MiniStack doesn't check them, it just needs *something* in that field.
2. **`s3.tf`** — created the `file-ledger-landing` bucket. This is where
   files will get uploaded.
3. **`iam.tf`** — created a role and permissions for a Lambda function that
   didn't exist yet, so it would be ready to plug in on Day 2. This is like
   preparing an employee's badge and door access *before* they start,
   instead of scrambling on day one.

We proved it worked by running:

```bash
terraform apply
aws --endpoint-url=http://localhost:4566 s3 ls
```

and seeing `file-ledger-landing` listed back — confirmation the bucket
really exists in MiniStack, not just in our Terraform files.

## Day 2 — making it actually detect duplicates

**Goal:** build the part that does the real work — noticing a file arrived,
fingerprinting it, and deciding "new," "duplicate," or "retry."

What we built:

1. **`dynamodb.tf`** — created the `file-ledger` table. Every row is one
   unique file, keyed by its SHA-256 fingerprint, with columns for its
   status, the last filename it was seen under, when it was first/last
   seen, and how many times we've encountered it.
2. **`src/ledger_logic.py`** — the actual decision-making, written as a
   small, plain Python function with no AWS involved at all:
   - Never seen this fingerprint before? → mark it `new`.
   - Seen it before, and it was already `new` or `duplicate`? → mark it
     `duplicate` and bump the counter (someone re-uploaded the same file).
   - Seen it before, but it was marked `failed`? → reset it to `new` so it
     gets a fresh attempt (this is the "retry" case).
3. **`src/handler.py`** — the glue code: download the uploaded file from
   S3, compute its fingerprint, ask `ledger_logic` what to do, write the
   result to DynamoDB.
4. **`lambda.tf`** — deployed that code as a real Lambda function and wired
   S3 so that *any* file landing in `file-ledger-landing` automatically
   wakes the function up — no manual triggering needed.
5. **`tests/test_ledger_logic.py`** — six small automated checks proving the
   decision logic is correct (new file, duplicate, retry-after-failure,
   etc.) that run in a fraction of a second with no AWS/MiniStack needed at
   all.

We proved the whole pipeline works end-to-end by hand:

```bash
# upload a file
aws --endpoint-url=http://localhost:4566 s3api put-object \
  --bucket file-ledger-landing --key test.txt --body test.txt --checksum-algorithm SHA256

# the Lambda fires automatically — check the ledger
aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name file-ledger
# → status: new, attempt_count: 1

# upload the exact same content again, under a different name
aws --endpoint-url=http://localhost:4566 s3api put-object \
  --bucket file-ledger-landing --key test-copy.txt --body test.txt --checksum-algorithm SHA256

# check again
aws --endpoint-url=http://localhost:4566 dynamodb get-item ...
# → status: duplicate, attempt_count: 2
```

That's the whole system working: upload → auto-trigger → fingerprint →
lookup → correct decision, with zero manual steps in between.

## What's next (not built yet)

- Something that actually *processes* a `new` file and can mark it
  `failed` if that processing errors out (right now, nothing produces a
  `failed` status — the retry logic is ready and tested, just unused).
- Safety features like bucket versioning, encryption, and a dead-letter
  queue for when something goes wrong mid-processing.

## Where to look for more detail

- [`README.md`](./README.md) — the current architecture, kept up to date as the project grows.
- [`day2-README.md`](./day2-README.md) — Day 2's build log, including real command output and the bugs we hit and fixed.
