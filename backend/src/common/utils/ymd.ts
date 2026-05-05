import { BadRequestException } from '@nestjs/common';
import { DateTime } from 'luxon';

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

/** True when [zone] is usable as a Luxon IANA identifier. */
export function isValidIanaTimeZone(zone: string): boolean {
  const z = zone.trim();
  if (!z) return false;
  return DateTime.now().setZone(z).isValid;
}

/**
 * Calendar day `YYYY-MM-DD` interpreted in [zone] (e.g. device `America/Los_Angeles`),
 * returned as UTC instants `[start, end)` suitable for filtering `DateTime` columns.
 */
export function parseDayBoundsInTimeZone(
  on: string,
  zone: string,
): { start: Date; end: Date } {
  if (!YMD.test(on)) {
    throw new BadRequestException('Invalid date; use YYYY-MM-DD');
  }
  if (!isValidIanaTimeZone(zone)) {
    throw new BadRequestException('Invalid IANA time zone');
  }
  const start = DateTime.fromISO(`${on}T00:00:00`, { zone });
  if (!start.isValid) {
    throw new BadRequestException('Invalid calendar day for time zone');
  }
  const end = start.plus({ days: 1 });
  return { start: start.toUTC().toJSDate(), end: end.toUTC().toJSDate() };
}
