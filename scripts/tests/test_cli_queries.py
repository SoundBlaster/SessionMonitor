"""Safety/statistics checks for the read-only CLI performance harness."""

from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'performance'))
from cli_queries import backup, percentile, summary


class QueryBenchmarkTests(unittest.TestCase):
    def test_backup_includes_committed_wal_but_not_an_open_transaction(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, destination = root / 'source.sqlite', root / 'snapshot.sqlite'
            connection = sqlite3.connect(source)
            try:
                connection.execute('PRAGMA journal_mode=WAL')
                connection.execute('CREATE TABLE records(value INTEGER)')
                connection.execute('INSERT INTO records VALUES (1)')
                connection.commit()
                connection.execute('INSERT INTO records VALUES (2)')
                backup(source, destination)
                with sqlite3.connect(destination) as snapshot:
                    self.assertEqual(snapshot.execute('SELECT value FROM records').fetchall(), [(1,)])
                self.assertEqual(connection.execute('SELECT value FROM records').fetchall(), [(1,), (2,)])
            finally:
                connection.rollback()
                connection.close()

    def test_existing_destination_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / 'source.sqlite'
            connection = sqlite3.connect(source)
            connection.execute('CREATE TABLE records(value INTEGER)')
            connection.close()
            destination = Path(temporary) / 'existing.sqlite'
            destination.write_bytes(b'preserve existing evidence')
            with self.assertRaises(ValueError):
                backup(source, destination)
            self.assertEqual(destination.read_bytes(), b'preserve existing evidence')

    def test_descriptive_statistics_and_nearest_rank(self):
        samples = [{'wall_seconds': value, 'cpu_seconds': 0.1, 'peak_rss_bytes': 100,
                    'stdout_bytes': 20} for value in range(1, 21)]
        result = summary(samples)
        self.assertEqual(result['wall_median_seconds'], 10.5)
        self.assertEqual(result['wall_p95_seconds'], 19)
        self.assertEqual(result['samples'], 20)
        self.assertEqual(percentile([3, 1, 2], 1), 3)
        with self.assertRaises(ValueError):
            percentile([], 0.95)


if __name__ == '__main__':
    unittest.main()
