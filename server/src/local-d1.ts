// Minimal D1-compatible wrapper for local Docker / Node development
import type Database from "better-sqlite3";

type Row = Record<string, unknown>;

class Stmt {
  constructor(
    private db: Database.Database,
    private sql: string,
    private bindings: unknown[] = []
  ) {}

  bind(...values: unknown[]) {
    return new Stmt(this.db, this.sql, values);
  }

  async first<T extends Row = Row>(): Promise<T | null> {
    const row = this.db.prepare(this.sql).get(...this.bindings) as T | undefined;
    return row ?? null;
  }

  async run() {
    const info = this.db.prepare(this.sql).run(...this.bindings);
    return {
      success: true,
      meta: { changes: info.changes, last_row_id: Number(info.lastInsertRowid) },
    };
  }

  async all<T extends Row = Row>() {
    const results = this.db.prepare(this.sql).all(...this.bindings) as T[];
    return { results, success: true };
  }
}

export class LocalD1Database {
  constructor(private db: Database.Database) {}

  prepare(sql: string) {
    return new Stmt(this.db, sql);
  }
}
