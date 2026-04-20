-- CreateEnum
CREATE TYPE "TimelineSlotStatus" AS ENUM ('UPCOMING', 'ACTIVE', 'DONE', 'MISSED', 'SKIPPED');

-- CreateTable
CREATE TABLE "TimelineSlot" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "startsAt" TIMESTAMP(3) NOT NULL,
    "endsAt" TIMESTAMP(3) NOT NULL,
    "title" TEXT NOT NULL,
    "iconKey" TEXT,
    "tag" TEXT,
    "soundLabel" TEXT,
    "status" "TimelineSlotStatus" NOT NULL DEFAULT 'UPCOMING',
    "linkedTaskId" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TimelineSlot_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "TimelineSlot_userId_startsAt_idx" ON "TimelineSlot"("userId", "startsAt");

ALTER TABLE "TimelineSlot" ADD CONSTRAINT "TimelineSlot_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "TimelineSlot" ADD CONSTRAINT "TimelineSlot_linkedTaskId_fkey" FOREIGN KEY ("linkedTaskId") REFERENCES "Task"("id") ON DELETE SET NULL ON UPDATE CASCADE;
