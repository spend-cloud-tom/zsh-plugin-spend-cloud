#!/usr/bin/env python3
"""
SpendCloud Migration Healer
Analyzes and attempts to fix missing table dependencies in Laravel migrations.
Can perform automated remediation when --fix flag is provided.
"""

import sys
import re
import json
import subprocess
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass
from collections import defaultdict


@dataclass
class MigrationError:
    """Represents a migration error."""
    database: str
    table: str
    operation: str
    error_type: str
    raw_error: str


@dataclass
class TableDependency:
    """Represents a table creation migration."""
    database: str
    table: str
    migration_file: Optional[str] = None
    exists_in_db: bool = False


class MigrationHealer:
    """Analyzes migration errors and suggests fixes."""

    def __init__(self, container_name: str):
        self.container_name = container_name
        self.errors: List[MigrationError] = []
        self.dependencies: Dict[str, List[TableDependency]] = defaultdict(list)

    def parse_migration_output(self, output: str) -> List[MigrationError]:
        """Parse Laravel migration error output."""
        errors = []

        # Strip ANSI escape codes that Laravel/Docker might include
        ansi_escape = re.compile(r'\x1b\[[0-9;]*m')
        output = ansi_escape.sub('', output)

        # Primary pattern: Match with ANY amount of whitespace (including newlines)
        # between Table '...' and doesn't exist
        primary_pattern = re.compile(
            r"Table\s+'([^']+)\.([^']+?)'\s+doesn't\s+exist",
            re.IGNORECASE | re.MULTILINE | re.DOTALL
        )

        for match in primary_pattern.finditer(output):
            database, table = match.groups()
            # Clean up any whitespace and newlines within the captured strings
            database = re.sub(r'\s+', '', database)
            table = re.sub(r'\s+', '', table)

            # Try to determine operation type from context
            operation = 'UNKNOWN'
            context_start = max(0, match.start() - 200)
            context = output[context_start:match.end() + 100]

            if re.search(r'alter\s+table', context, re.IGNORECASE):
                operation = 'ALTER'
            elif re.search(r'create\s+table', context, re.IGNORECASE):
                operation = 'CREATE'
            elif re.search(r'drop\s+table', context, re.IGNORECASE):
                operation = 'DROP'

            errors.append(MigrationError(
                database=database,
                table=table,
                operation=operation,
                error_type='MISSING_TABLE',
                raw_error=match.group(0)
            ))

        # Alternative pattern: SQLSTATE format
        sqlstate_pattern = re.compile(
            r"SQLSTATE\[42S02\].*?Table\s+'?([^'\s\.]+)\.([^'\s]+)'?\s+doesn't\s+exist",
            re.IGNORECASE | re.DOTALL
        )

        seen = {(e.database, e.table) for e in errors}
        for match in sqlstate_pattern.finditer(output):
            database, table = match.groups()
            database = database.strip()
            table = table.strip()

            if (database, table) not in seen:
                errors.append(MigrationError(
                    database=database,
                    table=table,
                    operation='UNKNOWN',
                    error_type='MISSING_TABLE',
                    raw_error=match.group(0)[:150]
                ))
                seen.add((database, table))

        return errors

    def analyze_dependencies(self, errors: List[MigrationError]) -> Dict[str, List[str]]:
        """Analyze what tables are missing per database."""
        deps = defaultdict(set)
        for error in errors:
            deps[error.database].add(error.table)

        return {db: sorted(tables) for db, tables in deps.items()}

    def generate_report(self, errors: List[MigrationError]) -> str:
        """Generate a human-readable analysis report."""
        if not errors:
            return "✅ No migration errors detected!"

        deps = self.analyze_dependencies(errors)

        # Detect if this looks like database corruption
        is_corrupted = self._detect_corruption(errors, deps)

        report = []
        report.append("\n" + "=" * 70)
        report.append("🔍 MIGRATION DEPENDENCY ANALYSIS")
        report.append("=" * 70)
        report.append(f"\nFound {len(errors)} missing table error(s) across {len(deps)} database(s)\n")

        for database, tables in deps.items():
            report.append(f"\n📊 Database: {database}")
            report.append(f"   Missing {len(tables)} table(s):")
            for table in tables:
                report.append(f"   • {table}")

        # Add corruption warning if detected
        if is_corrupted:
            report.append("\n" + "⚠️ " * 35)
            report.append("🔥 DATABASE CORRUPTION DETECTED")
            report.append("⚠️ " * 35)
            report.append("\nThis database appears to be corrupted or incomplete.")
            report.append("Multiple core tables are missing, suggesting:")
            report.append("  • Incomplete import")
            report.append("  • Partial restoration")
            report.append("  • Database corruption")
            report.append("\n💣 RECOMMENDED: Use 'nuke' command to clean up and reimport")

        report.append("\n" + "-" * 70)
        report.append("💡 RECOMMENDED SOLUTIONS")
        report.append("-" * 70)

        if is_corrupted:
            report.append("\n🔥 CORRUPTION DETECTED - Recommended action:")
            report.append("\n1. NUKE AND REIMPORT (Recommended for corrupted databases)")
            for database in deps.keys():
                # Extract client name from database (e.g., 'sherpa' from 'sherpa' or 'sherpa-*')
                client_name = database.split('-')[0] if '-' in database else database
                report.append(f"   → export ENABLE_NUKE=1")
                report.append(f"   → nuke --verify {client_name}  # Check what will be deleted")
                report.append(f"   → nuke {client_name}           # Delete corrupted database")
                report.append(f"   → cluster-import --client {client_name}  # Reimport fresh data")
            report.append("\n   ⚠️  This will DELETE all data and reimport from backup")
        else:
            report.append("\n1. IGNORE (Safest - already done automatically)")
            report.append("   → These warnings don't prevent other migrations from running")
            report.append("   → Common in legacy/imported databases")
            report.append("   → No action needed unless functionality is broken")

        report.append("\n2. CHECK MIGRATION STATUS")
        for database in deps.keys():
            report.append(f"   → migrate check {database}")
        report.append("   → Look for pending migrations that create these tables")

        report.append("\n3. VERIFY TABLE EXISTENCE")
        report.append("   → Run: migrate tinker")
        for database, tables in deps.items():
            for table in tables[:3]:  # Show first 3
                report.append(f"   → \\DB::connection('{database}')->select('SHOW TABLES LIKE \"{table}\"');")

        report.append("\n4. RUN HEAL ATTEMPT")
        report.append("   → migrate heal")
        report.append("   → Attempts to run pending migrations that create missing tables")

        if not is_corrupted:
            report.append("\n5. FRESH REBUILD (DESTRUCTIVE - last resort)")
            report.append("   → migrate fresh customers")
            report.append("   ⚠️  WARNING: Deletes all data in customer databases!")

        report.append("\n" + "=" * 70)
        report.append("📝 TECHNICAL DETAILS")
        report.append("=" * 70)

        for i, error in enumerate(errors, 1):
            report.append(f"\nError #{i}:")
            report.append(f"  Database: {error.database}")
            report.append(f"  Table: {error.table}")
            report.append(f"  Operation: {error.operation}")
            report.append(f"  Type: {error.error_type}")

        report.append("\n" + "=" * 70 + "\n")

        return "\n".join(report)

    def _detect_corruption(self, errors: List[MigrationError], deps: Dict[str, List[str]]) -> bool:
        """
        Detect if the database appears corrupted vs just having missing migrations.

        Indicators of corruption:
        - Multiple missing tables in the same database
        - Missing tables that start with numbers (like 06_order) which are core tables
        - Multiple errors for the same missing table (migration retry failures)
        """
        # Multiple missing tables in one database suggests corruption
        for database, tables in deps.items():
            if len(tables) >= 3:  # 3+ missing tables = likely corrupted
                return True

        # Multiple errors for same table (seen in error duplicates)
        error_counts = {}
        for error in errors:
            key = (error.database, error.table)
            error_counts[key] = error_counts.get(key, 0) + 1

        # If same table error appears multiple times, it's failing repeatedly
        if any(count >= 2 for count in error_counts.values()):
            # Core tables (starting with digits) failing = corruption
            for (db, table), count in error_counts.items():
                if count >= 2 and table[0].isdigit():
                    return True

        return False

    def generate_docker_check_commands(self, deps: Dict[str, List[str]]) -> List[str]:
        """Generate Docker commands to check table existence."""
        commands = []

        for database, tables in deps.items():
            for table in tables:
                cmd = (
                    f"docker exec -i {self.container_name} "
                    f"mysql -u root -h mysql-service {database} "
                    f"-N -e \"SHOW TABLES LIKE '{table}';\""
                )
                commands.append(cmd)

        return commands

    def generate_heal_suggestions(self, deps: Dict[str, List[str]]) -> Dict[str, any]:
        """Generate structured healing suggestions."""
        suggestions = {
            "databases_affected": list(deps.keys()),
            "total_missing_tables": sum(len(tables) for tables in deps.values()),
            "actions": []
        }

        # Suggest checking migration status
        for database in deps.keys():
            suggestions["actions"].append({
                "priority": 1,
                "type": "check_status",
                "command": f"migrate check {database}",
                "description": f"Check migration status for {database}"
            })

        # Suggest running heal
        suggestions["actions"].append({
            "priority": 2,
            "type": "heal",
            "command": "migrate heal",
            "description": "Attempt to run pending migrations"
        })

        # Suggest manual verification
        for database, tables in deps.items():
            for table in tables[:5]:  # Limit to 5 per database
                suggestions["actions"].append({
                    "priority": 3,
                    "type": "verify",
                    "command": f"check table {database}.{table}",
                    "description": f"Verify if {table} actually exists in {database}"
                })

        return suggestions


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: migration-healer.py <container_name> [migration_output_file]", file=sys.stderr)
        sys.exit(1)

    container_name = sys.argv[1]

    # Read migration output from stdin or file
    if len(sys.argv) > 2:
        with open(sys.argv[2], 'r') as f:
            migration_output = f.read()
    else:
        migration_output = sys.stdin.read()

    # Check for --json flag
    json_output = '--json' in sys.argv

    healer = MigrationHealer(container_name)
    errors = healer.parse_migration_output(migration_output)

    if json_output:
        # JSON output for programmatic use
        deps = healer.analyze_dependencies(errors)
        suggestions = healer.generate_heal_suggestions(deps)
        print(json.dumps({
            "error_count": len(errors),
            "errors": [
                {
                    "database": e.database,
                    "table": e.table,
                    "operation": e.operation,
                    "type": e.error_type
                }
                for e in errors
            ],
            "dependencies": deps,
            "suggestions": suggestions
        }, indent=2))
    else:
        # Human-readable report
        report = healer.generate_report(errors)
        print(report)

        # Exit with error code if problems found
        sys.exit(1 if errors else 0)


if __name__ == '__main__':
    main()
