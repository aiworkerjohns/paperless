#!/usr/bin/env python3
"""Duplicate document detection sweep for Paperless-ngx.
Uses paperless-ai RAG semantic search to find similar documents.
Tags duplicates with 'possible-duplicate'.
"""

import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime

PAPERLESS_URL = os.environ.get("PAPERLESS_URL", "http://paperless:8000")
PAPERLESS_TOKEN = os.environ.get("PAPERLESS_TOKEN", "")
AI_URL = os.environ.get("AI_URL", "http://paperless-ai:3000")
AI_API_KEY = os.environ.get("AI_API_KEY", "")
SIMILARITY_THRESHOLD = float(os.environ.get("SIMILARITY_THRESHOLD", "0.85"))
DUP_TAG_NAME = "possible-duplicate"


def log(msg):
    print(f"[duplicate-sweep] {datetime.now():%Y-%m-%d %H:%M:%S} {msg}", flush=True)


def api_call(url, method="GET", data=None, headers=None):
    hdrs = headers or {}
    if data is not None:
        body = json.dumps(data).encode()
        hdrs["Content-Type"] = "application/json"
    else:
        body = None
    req = urllib.request.Request(url, data=body, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except (urllib.error.URLError, json.JSONDecodeError) as e:
        log(f"  API error: {e}")
        return None


def paperless_api(path, method="GET", data=None):
    return api_call(
        f"{PAPERLESS_URL}{path}",
        method=method,
        data=data,
        headers={"Authorization": f"Token {PAPERLESS_TOKEN}"},
    )


def rag_search(query):
    return api_call(
        f"{AI_URL}/api/rag/search",
        method="POST",
        data={"query": query},
        headers={"x-api-key": AI_API_KEY, "Content-Type": "application/json"},
    )


def ensure_tag():
    """Ensure the possible-duplicate tag exists, return its ID."""
    resp = paperless_api(f"/api/tags/?name__iexact={DUP_TAG_NAME}")
    if resp and resp.get("results"):
        return resp["results"][0]["id"]

    log(f"Creating '{DUP_TAG_NAME}' tag...")
    resp = paperless_api(
        "/api/tags/",
        method="POST",
        data={"name": DUP_TAG_NAME, "color": "#e74c3c", "is_inbox_tag": False},
    )
    if resp:
        log(f"Created tag with ID {resp['id']}")
        return resp["id"]
    return None


def get_all_documents():
    """Fetch all documents from Paperless."""
    docs = []
    url = "/api/documents/?page_size=1000"
    while url:
        resp = paperless_api(url)
        if not resp:
            break
        docs.extend(resp.get("results", []))
        next_url = resp.get("next")
        if next_url:
            # next_url is absolute, extract path
            url = next_url.replace(PAPERLESS_URL, "")
        else:
            url = None
    return docs


def tag_document(doc_id, current_tags, dup_tag_id):
    """Add the duplicate tag to a document if not already present."""
    if dup_tag_id in current_tags:
        return
    new_tags = list(set(current_tags + [dup_tag_id]))
    paperless_api(f"/api/documents/{doc_id}/", method="PATCH", data={"tags": new_tags})
    log(f"  Tagged doc {doc_id} as '{DUP_TAG_NAME}'")


def add_duplicate_note(dupe_id, orig_id, orig_title):
    """Add a note on the duplicate doc linking to the original, if not already noted."""
    marker = f"Duplicate of document #{orig_id}"
    # Check existing notes
    notes = paperless_api(f"/api/documents/{dupe_id}/notes/")
    if notes:
        note_list = notes if isinstance(notes, list) else notes.get("results", notes)
        if isinstance(note_list, list):
            for n in note_list:
                if marker in n.get("note", ""):
                    return  # Already noted

    note_text = f"{marker}: {orig_title}\n/documents/{orig_id}/details"
    paperless_api(
        f"/api/documents/{dupe_id}/notes/",
        method="POST",
        data={"note": note_text},
    )
    log(f"  Added duplicate note on doc {dupe_id} -> original doc {orig_id}")


def main():
    if not PAPERLESS_TOKEN or not AI_API_KEY:
        log("ERROR: PAPERLESS_TOKEN and AI_API_KEY must be set")
        sys.exit(1)

    dup_tag_id = ensure_tag()
    if not dup_tag_id:
        log("ERROR: Could not create/find duplicate tag")
        sys.exit(1)

    docs = get_all_documents()
    log(f"Found {len(docs)} documents to check")

    if len(docs) < 2:
        log("Not enough documents to check for duplicates. Done.")
        return

    checked_pairs = set()
    duplicates_found = 0

    for doc in docs:
        doc_id = doc["id"]
        doc_title = doc["title"]

        results = rag_search(doc_title)
        if not results:
            continue

        if isinstance(results, dict):
            results = results.get("results", [])

        for r in results:
            match_id = r.get("doc_id") or r.get("id") or r.get("document_id")
            if not match_id or int(match_id) == doc_id:
                continue

            # Prefer cross_score (cross-encoder) over base score
            score = r.get("cross_score") or r.get("score", 0)
            if score < SIMILARITY_THRESHOLD:
                continue

            # Skip already-checked pairs
            pair = tuple(sorted([doc_id, int(match_id)]))
            if pair in checked_pairs:
                continue
            checked_pairs.add(pair)

            match_title = r.get("title", f"Document #{match_id}")
            match_id = int(match_id)

            # Determine which is newer (higher ID = imported later = the duplicate)
            if doc_id > match_id:
                dupe_id, dupe_tags, orig_id, orig_title = doc_id, doc.get("tags", []), match_id, match_title
            else:
                orig_id, orig_title = doc_id, doc_title
                dupe_id = match_id
                dupe_doc = paperless_api(f"/api/documents/{match_id}/")
                dupe_tags = dupe_doc.get("tags", []) if dupe_doc else []

            log(f"DUPLICATE: Doc {dupe_id} is a duplicate of Doc {orig_id} ({orig_title}) [score: {score:.3f}]")
            duplicates_found += 1

            # Only tag the newer document as possible-duplicate
            tag_document(dupe_id, dupe_tags, dup_tag_id)

            # Add a note on the duplicate linking to the original
            add_duplicate_note(dupe_id, orig_id, orig_title)

    log(f"Sweep complete. Found {duplicates_found} duplicate pair(s).")


if __name__ == "__main__":
    main()
