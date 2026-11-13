require "sqlite3"
require "monitor"
require "set"

module Tensaku
  # The SQLite database in Tensaku.home that holds every app's notes, the agents connected to them and
  # the page's selection. The dev server and every `tensaku mcp` open it at once: WAL lets readers run
  # while one process writes, writes take the database's write lock (BEGIN IMMEDIATE), and a process
  # waits up to five seconds for another's write to finish.
  #
  # Each write also adds a row to `changes`, so a reader asks "anything after the last change I saw?"
  # instead of reading every note, and Doorbell wakes the readers that wait.
  module Store
    FILE = "tensaku.sqlite3"
    BUSY_TIMEOUT = 5000

    # Raised whenever the schema changes. Tensaku isn't released, so the schema is one script that only
    # adds what is missing; a change to an existing table means deleting the database.
    VERSION = 2
    SCHEMA = <<~SQL
      CREATE TABLE IF NOT EXISTS projects (
        root TEXT PRIMARY KEY,
        remote TEXT,
        base_url TEXT,
        created_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        project TEXT NOT NULL REFERENCES projects(root) ON DELETE CASCADE,
        url TEXT NOT NULL,
        comment TEXT NOT NULL,
        status TEXT NOT NULL,
        targets TEXT NOT NULL DEFAULT '[]',
        rect TEXT,
        viewport TEXT,
        "commit" TEXT,
        session TEXT,
        agent TEXT,
        sent_at TEXT,
        delivered_at TEXT,
        delivered_to TEXT,
        archived_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS notes_project ON notes (project, archived_at, status);
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY,
        note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
        author TEXT NOT NULL,
        agent TEXT,
        text TEXT NOT NULL,
        at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS messages_note ON messages (note_id, id);
      CREATE TABLE IF NOT EXISTS agents (
        session TEXT NOT NULL,
        project TEXT NOT NULL REFERENCES projects(root) ON DELETE CASCADE,
        name TEXT NOT NULL,
        handle TEXT NOT NULL,
        listening INTEGER NOT NULL DEFAULT 0,
        idle INTEGER NOT NULL DEFAULT 0,
        cwd TEXT,
        pid INTEGER NOT NULL,
        started_at TEXT,
        last TEXT,
        seen_at REAL NOT NULL,
        PRIMARY KEY (session, project)
      );
      CREATE TABLE IF NOT EXISTS selections (
        project TEXT NOT NULL REFERENCES projects(root) ON DELETE CASCADE,
        tab TEXT NOT NULL,
        url TEXT,
        data TEXT NOT NULL,
        at TEXT NOT NULL,
        PRIMARY KEY (project, tab)
      );
      CREATE TABLE IF NOT EXISTS changes (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        project TEXT NOT NULL,
        kind TEXT NOT NULL,
        note_id TEXT,
        at REAL NOT NULL
      );
      CREATE INDEX IF NOT EXISTS changes_project ON changes (project, seq);
      CREATE TABLE IF NOT EXISTS screenshots (
        note_id TEXT PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
        png BLOB NOT NULL,
        width INTEGER NOT NULL,
        height INTEGER NOT NULL
      );
    SQL

    LOCK = Monitor.new

    module_function

    def path
      Tensaku.home.join(FILE)
    end

    # The process's connection, opened again after a fork (Puma workers) or when TENSAKU_HOME changes
    # (tests). Threads share it one at a time.
    def db
      LOCK.synchronize do
        if @db.nil? || @pid != Process.pid || @path != path
          @db = connect(path)
          @pid = Process.pid
          @path = path
        end
        @db
      end
    end

    # A write. Holds the database's write lock from the start, so what the block read is still true
    # when it writes. Nested calls join the outer transaction.
    # The apps a write changed (ring) are rung on the doorbell once it commits.
    def write
      LOCK.synchronize do
        connection = db
        return yield connection if connection.transaction_active?

        rings = Thread.current[:tensaku_rings] = Set.new
        begin
          result = connection.transaction(:immediate) { yield connection }
        ensure
          Thread.current[:tensaku_rings] = nil
        end
        rings.each { Doorbell.ring(it) }
        result
      end
    end

    # Wakes the readers of the app at root once the current write commits.
    def ring(root)
      Thread.current[:tensaku_rings]&.add(Pathname(root).expand_path.to_s)
    end

    def read
      LOCK.synchronize { yield db }
    end

    def connect(file)
      file.dirname.mkpath
      # Notes can quote unreleased work, so only this user can open the folder.
      file.dirname.chmod(0o700) unless Gem.win_platform?
      connection = SQLite3::Database.new(file.to_s, results_as_hash: true)
      connection.busy_timeout = BUSY_TIMEOUT
      connection.execute("PRAGMA journal_mode = WAL")
      connection.execute("PRAGMA foreign_keys = ON")
      connection.execute("PRAGMA synchronous = NORMAL")
      migrate(connection)
      connection
    end

    def migrate(connection)
      connection.transaction(:immediate) do
        next if connection.get_first_value("PRAGMA user_version").to_i >= VERSION

        connection.execute_batch(SCHEMA)
        connection.execute("PRAGMA user_version = #{VERSION}")
      end
    end

    # Forgets the connection, for tests that delete the database file.
    def reset!
      LOCK.synchronize do
        @db&.close
        @db = nil
      end
    end
  end
end
