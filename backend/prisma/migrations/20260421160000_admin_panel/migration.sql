-- Admin panel + mobile ops schema

CREATE TYPE "UserRole" AS ENUM ('USER', 'ADMIN', 'SUPERADMIN');
CREATE TYPE "UserPlan" AS ENUM ('FREE', 'PRO');
CREATE TYPE "RefreshTokenScope" AS ENUM ('USER', 'ADMIN');
CREATE TYPE "ErrorResolutionStatus" AS ENUM ('UNRESOLVED', 'IN_PROGRESS', 'RESOLVED');
CREATE TYPE "PushTargetType" AS ENUM ('ALL', 'SPECIFIC', 'SEGMENT');
CREATE TYPE "PushDevicePlatform" AS ENUM ('IOS', 'ANDROID');
CREATE TYPE "InsightMood" AS ENUM ('POSITIVE', 'NEUTRAL', 'WARNING');

ALTER TABLE "User" ADD COLUMN "role" "UserRole" NOT NULL DEFAULT 'USER';
ALTER TABLE "User" ADD COLUMN "displayName" TEXT;
ALTER TABLE "User" ADD COLUMN "username" TEXT;
ALTER TABLE "User" ADD COLUMN "avatarUrl" TEXT;
ALTER TABLE "User" ADD COLUMN "isBanned" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "User" ADD COLUMN "banReason" TEXT;
ALTER TABLE "User" ADD COLUMN "banExpiresAt" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN "plan" "UserPlan" NOT NULL DEFAULT 'FREE';
ALTER TABLE "User" ADD COLUMN "subscriptionExpiresAt" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN "lastActiveAt" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN "deviceOs" TEXT;
ALTER TABLE "User" ADD COLUMN "appVersion" TEXT;

CREATE UNIQUE INDEX "User_username_key" ON "User"("username") WHERE "username" IS NOT NULL;

ALTER TABLE "RefreshToken" ADD COLUMN "scope" "RefreshTokenScope" NOT NULL DEFAULT 'USER';

CREATE TABLE "ErrorLog" (
    "id" TEXT NOT NULL,
    "userId" TEXT,
    "errorType" TEXT NOT NULL,
    "errorMessage" TEXT NOT NULL,
    "screen" TEXT,
    "appVersion" TEXT,
    "deviceOs" TEXT,
    "fingerprint" TEXT NOT NULL,
    "status" "ErrorResolutionStatus" NOT NULL DEFAULT 'UNRESOLVED',
    "internalNote" TEXT,
    "assignedTo" TEXT,
    "resolvedById" TEXT,
    "resolvedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "ErrorLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "ErrorLog_fingerprint_createdAt_idx" ON "ErrorLog"("fingerprint", "createdAt");
CREATE INDEX "ErrorLog_userId_createdAt_idx" ON "ErrorLog"("userId", "createdAt");
CREATE INDEX "ErrorLog_status_createdAt_idx" ON "ErrorLog"("status", "createdAt");

ALTER TABLE "ErrorLog" ADD CONSTRAINT "ErrorLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ErrorLog" ADD CONSTRAINT "ErrorLog_resolvedById_fkey" FOREIGN KEY ("resolvedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "FeatureFlag" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "isEnabled" BOOLEAN NOT NULL DEFAULT false,
    "rolloutPercentage" INTEGER NOT NULL DEFAULT 0,
    "enabledForUserIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "description" TEXT,
    "scheduledEnableAt" TIMESTAMP(3),
    "scheduledDisableAt" TIMESTAMP(3),
    "updatedByUserId" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "FeatureFlag_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "FeatureFlag_key_key" ON "FeatureFlag"("key");
ALTER TABLE "FeatureFlag" ADD CONSTRAINT "FeatureFlag_updatedByUserId_fkey" FOREIGN KEY ("updatedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "AppConfig" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "description" TEXT,
    "isPublic" BOOLEAN NOT NULL DEFAULT false,
    "updatedByUserId" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "AppConfig_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AppConfig_key_key" ON "AppConfig"("key");
ALTER TABLE "AppConfig" ADD CONSTRAINT "AppConfig_updatedByUserId_fkey" FOREIGN KEY ("updatedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "AuditLog" (
    "id" TEXT NOT NULL,
    "adminUserId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "targetType" TEXT NOT NULL,
    "targetId" TEXT,
    "oldValue" JSONB,
    "newValue" JSONB,
    "ipAddress" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "AuditLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "AuditLog_adminUserId_createdAt_idx" ON "AuditLog"("adminUserId", "createdAt");
CREATE INDEX "AuditLog_action_createdAt_idx" ON "AuditLog"("action", "createdAt");
ALTER TABLE "AuditLog" ADD CONSTRAINT "AuditLog_adminUserId_fkey" FOREIGN KEY ("adminUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "AdminFailedLogin" (
    "id" TEXT NOT NULL,
    "emailNormalized" TEXT NOT NULL,
    "ipAddress" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "AdminFailedLogin_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "AdminFailedLogin_emailNormalized_createdAt_idx" ON "AdminFailedLogin"("emailNormalized", "createdAt");
CREATE INDEX "AdminFailedLogin_ipAddress_createdAt_idx" ON "AdminFailedLogin"("ipAddress", "createdAt");

CREATE TABLE "ErrorAlertConfig" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "maxOccurrences" INTEGER NOT NULL DEFAULT 10,
    "windowMinutes" INTEGER NOT NULL DEFAULT 60,
    "slackWebhookUrl" TEXT,
    "alertEmail" TEXT,
    "scrubKeywords" JSONB,
    "isEnabled" BOOLEAN NOT NULL DEFAULT true,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "ErrorAlertConfig_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ErrorAlertConfig_name_key" ON "ErrorAlertConfig"("name");

CREATE TABLE "PushDevice" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "platform" "PushDevicePlatform" NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "PushDevice_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PushDevice_userId_token_key" ON "PushDevice"("userId", "token");
CREATE INDEX "PushDevice_userId_idx" ON "PushDevice"("userId");
ALTER TABLE "PushDevice" ADD CONSTRAINT "PushDevice_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "PushNotification" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "targetType" "PushTargetType" NOT NULL,
    "targetUserIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "segmentFilter" JSONB,
    "sentCount" INTEGER NOT NULL DEFAULT 0,
    "openedCount" INTEGER NOT NULL DEFAULT 0,
    "scheduledAt" TIMESTAMP(3),
    "sentAt" TIMESTAMP(3),
    "createdByUserId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "PushNotification_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "PushNotification" ADD CONSTRAINT "PushNotification_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "AiCoachLog" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "messageUser" TEXT NOT NULL,
    "messageAi" TEXT NOT NULL,
    "tokensUsed" INTEGER,
    "sessionId" TEXT,
    "wasHelpful" BOOLEAN,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "AiCoachLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "AiCoachLog_userId_createdAt_idx" ON "AiCoachLog"("userId", "createdAt");
ALTER TABLE "AiCoachLog" ADD CONSTRAINT "AiCoachLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "AiSuggestion" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "subtitle" TEXT NOT NULL,
    "icon" TEXT,
    "targetCondition" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "shownCount" INTEGER NOT NULL DEFAULT 0,
    "dismissedCount" INTEGER NOT NULL DEFAULT 0,
    "clickCount" INTEGER NOT NULL DEFAULT 0,
    "variantParentId" TEXT,
    "createdByUserId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "AiSuggestion_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "AiSuggestion" ADD CONSTRAINT "AiSuggestion_variantParentId_fkey" FOREIGN KEY ("variantParentId") REFERENCES "AiSuggestion"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "AiSuggestion" ADD CONSTRAINT "AiSuggestion_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "AiInsightTemplate" (
    "id" TEXT NOT NULL,
    "mood" "InsightMood" NOT NULL,
    "title" TEXT NOT NULL,
    "subtitle" TEXT NOT NULL,
    "icon" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "AiInsightTemplate_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AiInsightTemplate_mood_key" ON "AiInsightTemplate"("mood");

CREATE TABLE "Sound" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "emoji" TEXT,
    "fileUrl" TEXT NOT NULL,
    "durationSeconds" INTEGER,
    "categoryTag" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "playCount" INTEGER NOT NULL DEFAULT 0,
    "deletedAt" TIMESTAMP(3),
    "createdByUserId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "Sound_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "Sound" ADD CONSTRAINT "Sound_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "Category" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "emoji" TEXT,
    "themeColor" TEXT,
    "defaultSoundId" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdByUserId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "Category_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "Category_sortOrder_idx" ON "Category"("sortOrder");
ALTER TABLE "Category" ADD CONSTRAINT "Category_defaultSoundId_fkey" FOREIGN KEY ("defaultSoundId") REFERENCES "Sound"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Category" ADD CONSTRAINT "Category_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
