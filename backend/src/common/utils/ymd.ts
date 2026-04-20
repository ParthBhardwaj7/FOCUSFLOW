import { BadRequestException } from '@nestjs/common';

const YMD = /^\d{4}-\d{2}-\d{2}$/;

/** Calendar day `YYYY-MM-DD` as UTC midnight (matches existing task `scheduledOn` semantics). */
export function parseYmdUtcStart(on: string): Date {
  if (!YMD.test(on)) {
    throw new BadRequestException('Invalid date; use YYYY-MM-DD');
  }
  return new Date(`${on}T00:00:00.000Z`);
}

/** `[start, end)` UTC bounds for all instants that fall on that calendar day in UTC-date terms. */
export function parseDayUtcBounds(on: string): { start: Date; end: Date } {
  const start = parseYmdUtcStart(on);
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 1);
  return { start, end };
}
