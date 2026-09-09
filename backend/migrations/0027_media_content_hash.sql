BEGIN;

-- Exact-duplicate detection for proof forensics (#47).
--
-- `etag` was the obvious candidate and it is not good enough. S3 and R2 set
-- it to the MD5 of the body only for single-part uploads; a multipart upload
-- gets a hash *of part hashes* with a `-N` suffix, which is not comparable
-- across objects that were uploaded in different numbers of parts. Bsheel
-- allows submissions up to 50 MB, so multipart is reachable in practice and
-- comparing etags would silently stop matching exactly on the large files
-- someone is most likely to be recycling.
--
-- So the hash is computed over the bytes we actually read, once, during the
-- forensics pass. It is separate from `perceptual_hash` on purpose: a
-- byte-identical file is decisive evidence, whereas two images can share a
-- difference hash while differing (two photographs of a blank wall hash
-- alike). Collapsing them would lose that distinction.
ALTER TABLE media_objects ADD COLUMN IF NOT EXISTS content_md5 text
  CHECK (content_md5 IS NULL OR content_md5 ~ '^[0-9a-f]{32}$');

COMMENT ON COLUMN media_objects.content_md5 IS
  'MD5 of the stored bytes (#47), computed during the forensics pass. Not '
  'taken from the storage ETag, which is a hash of part hashes for multipart '
  'uploads and therefore not comparable between objects.';

-- Exact-duplicate lookup. Partial on ready submission objects because those
-- are the only ones that can be recycled proof.
CREATE INDEX IF NOT EXISTS media_objects_content_md5_idx
  ON media_objects (content_md5)
  WHERE content_md5 IS NOT NULL AND kind = 'submission'
    AND status = 'ready' AND deleted_at IS NULL;

COMMIT;
