#!/usr/bin/env python3
"""
Reset all AI-assigned metadata and trigger a full reprocess.

Clears correspondents, document types, titles, and AI tags from all documents,
deletes orphaned correspondents/doc types, resets paperless-ai processing state,
and triggers a rescan.

Usage:
  docker exec paperless python3 /custom-init/reset-ai-metadata.py
"""
import os
import sys
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "paperless.settings")
sys.path.insert(0, "/usr/src/paperless/src")
django.setup()

from documents.models import Document, Correspondent, DocumentType, Tag

# Tags to preserve on documents (everything else gets removed)
KEEP_TAGS = {
    "inbox",
    "paperless-gpt-ocr-complete",
    "paperless-gpt-ocr-auto",
    "paperless-gpt-auto",
    "paperless-gpt-manual",
}

print("=== AI Metadata Reset ===")
print()

# 1. Strip AI-assigned data from all documents
docs = Document.objects.all()
doc_count = docs.count()
print(f"Processing {doc_count} documents...")

keep_tag_ids = set(
    Tag.objects.filter(name__in=KEEP_TAGS).values_list("id", flat=True)
)

for doc in docs:
    # Clear correspondent and document type
    doc.correspondent = None
    doc.document_type = None
    # Reset title to original filename (without extension)
    if doc.original_filename:
        doc.title = os.path.splitext(doc.original_filename)[0]
    doc.save()

    # Remove all tags except preserved ones
    current_tags = set(doc.tags.values_list("id", flat=True))
    remove_tags = current_tags - keep_tag_ids
    if remove_tags:
        doc.tags.remove(*remove_tags)

print(f"  Cleared metadata on {doc_count} documents")

# 2. Delete all correspondents (AI-created, will be recreated)
corr_count = Correspondent.objects.count()
Correspondent.objects.all().delete()
print(f"  Deleted {corr_count} correspondents")

# 3. Delete all document types (will be recreated by phase6/defaults)
# Actually keep these - they're created by the installer, not AI
# Only delete if they look AI-generated (not in our standard set)
STANDARD_DOC_TYPES = {
    "Invoice", "Receipt", "Statement", "Contract", "Insurance", "Letter",
    "Report", "Certificate", "Identity", "Tax Return", "Payslip", "Manual",
    "Quote", "Purchase Order", "Expense Report", "Form",
}
ai_doc_types = DocumentType.objects.exclude(name__in=STANDARD_DOC_TYPES)
ai_dt_count = ai_doc_types.count()
ai_doc_types.delete()
print(f"  Deleted {ai_dt_count} non-standard document types")

# 4. Reset paperless-ai processing state
ai_tag = Tag.objects.filter(name="ai-processed").first()
if ai_tag:
    tagged = Document.objects.filter(tags=ai_tag)
    count = tagged.count()
    for doc in tagged:
        doc.tags.remove(ai_tag)
    print(f"  Removed ai-processed tag from {count} documents")

print()
print("Reset complete. Trigger a rescan in paperless-ai to reprocess all documents.")
print("  Via UI:  Press 'Reprocess All' in the AI chat panel")
print("  Via CLI: curl -X POST http://localhost:3000/api/reset-all-documents -H 'Content-Type: application/json' && curl http://localhost:3000/api/scan/now")
