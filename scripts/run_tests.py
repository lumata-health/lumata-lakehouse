#!/usr/bin/env python3
"""
SCD Test Runner for sf_user Pipeline
This script executes all SCD-related tests in the proper order and generates reports
Requirements: 4.1, 4.2, 5.1, 7.1 - Comprehensive SCD testing execution
"""

import subprocess
import json
import yaml
import sys
from datetime import datetime
from pathlib import Path
import argparse

class SCDTestRunner:
    def __init__(self, profiles_dir=".", target="dev"):
        self.profiles_dir = profiles_dir
        self.target = target
        self.test_results = []
        
    def load_test_config(self):
        """Load test configuration from YAML file"""
        config_path = Path("tests/test_config.yml")
        if config_path.exists():
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        return {}
    
    def run_dbt_command(self, command, capture_output=True):
        """Execute a dbt command and return results"""
        full_command = f"dbt {command} --profiles-dir {self.profiles_dir} --target {self.target}"
        
        print(f"Executing: {full_command}")
        
        try:
            result = subprocess.run(
                full_command.split(),
                capture_output=capture_output,
                text=True,
                check=False
            )
            
            return {
                'command': command,
                'returncode': result.returncode,
                'stdout': result.stdout if capture_output else '',
                'stderr': result.stderr if capture_output else '',
                'success': result.returncode == 0
            }
        except Exception as e:
            return {
                'command': command,
                'returncode': -1,
                'stdout': '',
                'stderr': str(e),
                'success': False
            }
    
    def run_test_group(self, group_name, tests, severity="warn"):
        """Run a group of tests"""
        print(f"\n{'='*60}")
        print(f"Running test group: {group_name}")
        print(f"{'='*60}")
        
        group_results = []
        
        for test in tests:
            if isinstance(test, str):
                # Singular test
                test_command = f"test --select {test}"
            elif isinstance(test, dict):
                # Generic test or other configuration
                test_name = list(test.keys())[0]
                test_command = f"test --select {test_name}"
            else:
                continue
                
            result = self.run_dbt_command(test_command)
            result['test_name'] = test if isinstance(test, str) else test_name
            result['group'] = group_name
            result['severity'] = severity
            
            group_results.append(result)
            
            # Print immediate feedback
            status = "✅ PASS" if result['success'] else "❌ FAIL"
            print(f"{status} {result['test_name']}")
            
        return group_results
    
    def run_all_tests(self):
        """Run all SCD tests in the configured order"""
        print("Starting SCD Test Suite for sf_user Pipeline")
        print(f"Target: {self.target}")
        print(f"Timestamp: {datetime.now().isoformat()}")
        
        config = self.load_test_config()
        test_groups = config.get('test_groups', {})
        
        # Default test execution if no config found
        if not test_groups:
            test_groups = {
                'data_quality': {
                    'tests': ['test_sf_user_data_quality_comprehensive'],
                    'severity': 'error'
                },
                'scd_integrity': {
                    'tests': [
                        'test_scd_integrity_sf_user',
                        'test_scd_integrity_comprehensive',
                        'test_scd_is_current_flag_logic'
                    ],
                    'severity': 'error'
                },
                'scd_logic': {
                    'tests': [
                        'test_scd_type2_logic_correctness',
                        'test_scd_currency_management_sf_user',
                        'test_scd_tracked_fields_sf_user'
                    ],
                    'severity': 'error'
                },
                'scd_continuity': {
                    'tests': ['test_scd_no_gaps_overlaps'],
                    'severity': 'error'
                }
            }
        
        # Execute test groups in order
        all_results = []
        failed_groups = []
        
        for group_name, group_config in test_groups.items():
            tests = group_config.get('tests', [])
            severity = group_config.get('severity', 'warn')
            
            group_results = self.run_test_group(group_name, tests, severity)
            all_results.extend(group_results)
            
            # Check if any critical tests failed
            if severity == 'error' and any(not r['success'] for r in group_results):
                failed_groups.append(group_name)
                print(f"\n❌ Critical test group '{group_name}' failed!")
                
                # Stop execution if critical tests fail
                if group_name in ['data_quality', 'scd_integrity']:
                    print("Stopping execution due to critical test failures.")
                    break
        
        self.test_results = all_results
        return self.generate_test_report()
    
    def generate_test_report(self):
        """Generate a comprehensive test report"""
        total_tests = len(self.test_results)
        passed_tests = sum(1 for r in self.test_results if r['success'])
        failed_tests = total_tests - passed_tests
        
        report = {
            'timestamp': datetime.now().isoformat(),
            'target': self.target,
            'summary': {
                'total_tests': total_tests,
                'passed': passed_tests,
                'failed': failed_tests,
                'success_rate': round((passed_tests / total_tests * 100), 2) if total_tests > 0 else 0
            },
            'test_results': self.test_results
        }
        
        # Print summary
        print(f"\n{'='*60}")
        print("SCD TEST SUITE SUMMARY")
        print(f"{'='*60}")
        print(f"Total Tests: {total_tests}")
        print(f"Passed: {passed_tests}")
        print(f"Failed: {failed_tests}")
        print(f"Success Rate: {report['summary']['success_rate']}%")
        
        if failed_tests > 0:
            print(f"\n❌ FAILED TESTS:")
            for result in self.test_results:
                if not result['success']:
                    print(f"  - {result['test_name']} ({result['group']})")
        else:
            print(f"\n✅ ALL TESTS PASSED!")
        
        # Save report to file
        report_file = f"test_results_{self.target}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"\nDetailed report saved to: {report_file}")
        
        return report
    
    def run_performance_tests(self):
        """Run performance-specific tests"""
        print("\nRunning SCD Performance Tests...")
        
        # Run comprehensive SCD test macro
        result = self.run_dbt_command("run-operation test_scd_comprehensive")
        
        if result['success']:
            print("✅ SCD Performance Tests completed successfully")
        else:
            print("❌ SCD Performance Tests failed")
            print(result['stderr'])
        
        return result

def main():
    parser = argparse.ArgumentParser(description='Run SCD tests for sf_user pipeline')
    parser.add_argument('--target', default='dev', help='dbt target environment')
    parser.add_argument('--profiles-dir', default='.', help='dbt profiles directory')
    parser.add_argument('--performance-only', action='store_true', help='Run only performance tests')
    parser.add_argument('--no-performance', action='store_true', help='Skip performance tests')
    
    args = parser.parse_args()
    
    runner = SCDTestRunner(profiles_dir=args.profiles_dir, target=args.target)
    
    if args.performance_only:
        result = runner.run_performance_tests()
        sys.exit(0 if result['success'] else 1)
    
    # Run main test suite
    report = runner.run_all_tests()
    
    # Run performance tests unless skipped
    if not args.no_performance:
        runner.run_performance_tests()
    
    # Exit with appropriate code
    sys.exit(0 if report['summary']['failed'] == 0 else 1)

if __name__ == "__main__":
    main()