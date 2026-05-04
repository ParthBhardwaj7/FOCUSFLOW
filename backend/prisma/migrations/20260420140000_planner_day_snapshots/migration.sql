-- CreateTable
CREATE TABLE "PlannerDaySnapshot" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "dayOn" DATE NOT NULL,
    "slots" JSONB NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PlannerDaySnapshot_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PlannerDaySnapshot_userId_dayOn_key" ON "PlannerDaySnapshot"("userId", "dayOn");

CREATE INDEX "PlannerDaySnapshot_userId_dayOn_idx" ON "PlannerDaySnapshot"("userId", "dayOn");

ALTER TABLE "PlannerDaySnapshot" ADD CONSTRAINT "PlannerDaySnapshot_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
