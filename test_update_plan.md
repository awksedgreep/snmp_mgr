# SNMPMgr Test Update Plan - snmp_lib Migration

## Overview

This document tracks the systematic replacement of existing test files with focused snmp_lib integration tests. The goal is to replace tests that were testing custom SNMP implementation details with tests that validate snmp_lib integration.

## Test File Priority Classification

### High Priority Tests ✅ COMPLETED (6 files)
These are the core API and functionality tests that users interact with directly.

1. **test/snmp_mgr_test.exs** ✅ COMPLETED
   - Status: Replaced with focused API contract validation
   - Focus: Main API functions return expected formats through snmp_lib
   - Notes: Tests core API integration rather than implementation details

2. **test/simple_integration_test.exs** ✅ COMPLETED
   - Status: Replaced with basic snmp_lib integration validation
   - Focus: Basic operations, configuration, error handling through snmp_lib
   - Notes: Simple integration tests for snmp_lib backend

3. **test/integration_test.exs** ✅ COMPLETED
   - Status: Replaced with comprehensive snmp_lib integration tests
   - Focus: Complete integration flows, multi-operations, performance through snmp_lib
   - Notes: Tests full integration rather than simulator-specific functionality

4. **test/unit/core_operations_test.exs** ✅ COMPLETED
   - Status: Replaced with SnmpLib.Manager integration tests
   - Focus: Core SNMP operations through snmp_lib, OID processing through SnmpLib.OID
   - Notes: Uses SNMPSimulator with 100ms timeouts for efficient testing

5. **test/unit/bulk_operations_test.exs** ✅ COMPLETED
   - Status: Replaced with SnmpLib.Manager bulk operation tests
   - Focus: GET-BULK operations through snmp_lib, parameter validation, performance
   - Notes: Tests bulk vs individual operation efficiency with realistic expectations

6. **test/unit/table_walking_test.exs** ✅ COMPLETED
   - Status: Replaced with snmp_lib table walking integration tests
   - Focus: Walk operations using snmp_lib, version adaptation (v1/v2c), table operations
   - Notes: Tests table operations, Walk module, and Table module integration with snmp_lib

### Medium Priority Tests ✅ COMPLETED (7 files)

7. **test/integration/engine_integration_test.exs** ✅ COMPLETED
   - Status: Replaced with comprehensive snmp_lib backend integration tests
   - Focus: End-to-end snmp_lib integration across all operation types
   - Notes: Replaced custom engine ecosystem tests with snmp_lib backend validation

8. **test/unit/error_comprehensive_test.exs** ✅ COMPLETED
   - Status: Replaced with snmp_lib error handling integration tests
   - Focus: Error format consistency through snmp_lib, SnmpLib.OID error integration
   - Notes: Tests error handling across all scenarios, retry mechanisms, multi-operation resilience

9. **test/unit/error_handling_retry_test.exs** ✅ COMPLETED
   - Status: Replaced with snmp_lib error handling and retry integration tests
   - Focus: Network/protocol error handling, timeout management, retry logic through snmp_lib
   - Notes: Tests error handling across all scenarios, retry mechanisms, multi-operation resilience

10. **test/unit/metrics_comprehensive_test.exs** ✅ COMPLETED
    - Status: Replaced with snmp_lib metrics integration tests
    - Focus: Metrics collection during snmp_lib operations, response times, operation tracking
    - Notes: Tests application-level metrics during SNMP operations, bulk vs individual metrics

11. **test/unit/config_comprehensive_test.exs** ✅ COMPLETED
    - Status: Replaced with snmp_lib configuration integration tests
    - Focus: Configuration integration with snmp_lib operations, version-specific behavior
    - Notes: Tests how config affects snmp_lib calls, option merging, version handling

12. **test/unit/mib_comprehensive_test.exs** ✅ COMPLETED
    - Status: Replaced with SnmpLib.MIB integration tests
    - Focus: MIB integration with SnmpLib.MIB capabilities, name resolution with SNMP operations
    - Notes: Tests enhanced MIB functionality with snmp_lib, reverse lookup integration

13. **test/unit/multi_target_operations_test.exs** ✅ COMPLETED
    - Status: Replaced with snmp_lib multi-operation integration tests
    - Focus: Multi-target operations through snmp_lib, concurrent operations, bulk operations
    - Notes: Tests concurrent operations via snmp_lib, table operations, multi-operation scenarios

### Low Priority Tests ⏸️ PENDING (10 files)
These test specific modules or edge cases.

14. **test/unit/oid_comprehensive_test.exs** ✅ NOT NEEDED
    - Status: No separate file needed - OID handling fully delegated to SnmpLib.OID
    - Focus: OID processing integration already covered in core_operations_test.exs
    - Notes: SnmpLib.OID.normalize() used throughout codebase, integration tested in existing tests

15. **test/unit/pdu_comprehensive_test.exs** ✅ NOT NEEDED  
    - Status: No separate file needed - PDU handling fully delegated to SnmpLib.PDU
    - Focus: PDU processing integration already covered in engine and core tests
    - Notes: SnmpLib.PDU used for all build/encode/decode operations, integration tested in existing tests

16. **test/unit/pdu_test.exs** ✅ NOT NEEDED
    - Status: No separate file needed - PDU handling fully delegated to SnmpLib.PDU
    - Focus: Legacy PDU tests not needed, SnmpLib.PDU handles all PDU operations
    - Notes: PDU integration tested in engine_integration_test.exs and core_operations_test.exs

17. **test/unit/transport_test.exs** ✅ NOT NEEDED
    - Status: No separate file needed - Transport handling fully delegated to SnmpLib.Manager
    - Focus: Network transport integration already covered in core and integration tests
    - Notes: SnmpLib.Manager handles all UDP transport, integration tested in existing tests

18. **test/unit/types_comprehensive_test.exs** ✅ COMPLETED
    - Status: Replaced with focused application-level type testing
    - Focus: Type inference, encoding/decoding, integration with snmp_lib SET operations
    - Notes: Tests only SNMPMgr.Types functionality (convenience features), not low-level protocol handling

19. **test/unit/pool_comprehensive_test.exs** ✅ NOT NEEDED
    - Status: No separate file needed - Connection pooling fully delegated to snmp_lib
    - Focus: Connection pooling handled internally by SnmpLib.Manager
    - Notes: No Pool module exists, pooling integration tested in existing snmp_lib operation tests

20. **test/unit/router_comprehensive_test.exs** ⏸️ PENDING
    - Status: May need removal
    - Focus: N/A (Router module was removed)
    - Notes: Routing is now application-level over snmp_lib

21. **test/unit/circuit_breaker_comprehensive_test.exs** ⏸️ PENDING
    - Status: May need updates
    - Focus: Circuit breaker patterns at application level
    - Notes: Application-level circuit breaking, not protocol-level

22. **test/unit/performance_scale_test.exs** ⏸️ PENDING
    - Status: Needs updates for snmp_lib
    - Focus: Performance testing through snmp_lib backend
    - Notes: Should test snmp_lib performance characteristics

23. **test/unit/chaos_testing_test.exs** ⏸️ PENDING
    - Status: Needs updates for snmp_lib
    - Focus: Chaos testing with snmp_lib backend
    - Notes: Should test application resilience with snmp_lib

### Specialized Tests ⏸️ PENDING (3 files)
These are edge case or compliance tests.

24. **test/unit/asn1_edge_cases_test.exs** ⏸️ PENDING
    - Status: May need removal
    - Focus: N/A (ASN.1 handling now done by snmp_lib)
    - Notes: ASN.1 encoding/decoding is handled by snmp_lib

25. **test/unit/ber_encoding_compliance_test.exs** ⏸️ PENDING
    - Status: May need removal
    - Focus: N/A (BER encoding now done by snmp_lib)
    - Notes: BER encoding compliance is handled by snmp_lib

26. **test/unit/snmpv2c_exception_values_test.exs** ⏸️ PENDING
    - Status: May need updates
    - Focus: SNMPv2c exception handling through snmp_lib
    - Notes: Should test exception value handling via snmp_lib

## Current Status Summary

- **Total Test Files**: 26
- **High Priority**: 6 files ✅ COMPLETED
- **Medium Priority**: 7 files ✅ COMPLETED
- **Low Priority**: 10 files (all pending)
- **Specialized**: 3 files (all pending)

## Next Steps

### Currently Working On
**Low Priority Tests** - Starting with tests for removed modules that should be cleaned up

### Replacement Strategy

1. **For Removed Modules**: Tests for PDU, Transport, Pool, Types modules should be removed since these are now handled by snmp_lib
2. **For Application Modules**: Tests for Config, MIB, Metrics, etc. should be updated to test integration with snmp_lib
3. **For Integration Tests**: Focus on validating snmp_lib integration rather than custom implementation details

### Test Replacement Principles

1. **Focus on Integration**: Test how SNMPMgr integrates with snmp_lib, not snmp_lib internals
2. **Use SNMPSimulator**: All tests should use local simulator with 100ms timeouts
3. **Test Application Value**: Test the value-add SNMPMgr provides over raw snmp_lib
4. **Maintain Coverage**: Ensure we don't lose important test coverage during replacement
5. **User-Focused**: Tests should validate user-facing functionality and error handling

## Completion Criteria

- All high and medium priority tests replaced with snmp_lib integration tests
- Tests for removed modules cleaned up or removed
- Test suite runs efficiently with local simulator
- Coverage maintained for user-facing functionality
- Documentation updated to reflect new test architecture