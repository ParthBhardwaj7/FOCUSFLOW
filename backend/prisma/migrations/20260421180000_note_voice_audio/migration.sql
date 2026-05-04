-- Voice notes: optional audio file on disk, referenced by relative path.
ALTER TABLE "Note" ADD COLUMN "audioKey" TEXT;
