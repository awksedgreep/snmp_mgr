# SNMPMgr to SnmpLib Migration Plan

## Overview
Systematic migration from custom SNMP implementation to the standardized `snmp_lib` library (v0.2.0).
This migration will improve reliability, maintainability, and RFC compliance while preserving existing functionality.

## Current State Assessment
- **Starting Point**: May 31st codebase with substantial custom SNMP implementation
- **Test Status**: 3 real test failures to address
- **Architecture**: Custom PDU encoding/decoding, routing, circuit breaker, pooling
- **Dependencies**: `snmp_lib` v0.2.0 now added to mix.exs

## Migration Strategy

### Phase 1: Foundation and Core Operations (Week 1)
**Goal**: Replace core SNMP operations with snmp_lib equivalents

#### 1.1 PDU Module Migration ✅ COMPLETED
- **Current**: ~~`lib/snmp_mgr/pdu.ex` with custom ASN.1 BER encoding~~ **REMOVED**
- **Target**: Use `SnmpLib.PDU` for all PDU operations ✅
- **Tasks**:
  - ~~Create adapter layer `SNMPMgr.PDU.Adapter`~~ **NOT NEEDED - direct replacement**
  - ✅ Replaced all `SNMPMgr.PDU` calls with `SnmpLib.PDU` calls
  - ✅ Updated `lib/snmp_mgr/core.ex` to use `SnmpLib.PDU`
  - ✅ Updated `lib/snmp_mgr/engine.ex` to use `SnmpLib.PDU`
  - ✅ Updated `lib/snmp_mgr/performance_test.ex` to use `SnmpLib.PDU`
  - ✅ Removed custom PDU module entirely
  - ✅ Removed PDU-specific test files (functionality tested in snmp_lib)

#### 1.2 Core Operations Update
- **Current**: `lib/snmp_mgr/core.ex` with direct SNMP calls
- **Target**: Route through `SnmpLib.Client`
- **Tasks**:
  - Update `get/3`, `get_next/3`, `get_bulk/4` to use `SnmpLib.Client`
  - Implement proper error mapping from `SnmpLib.Error` to existing error format
  - Ensure timeout and retry logic compatibility
  - Maintain existing logging and metrics collection

#### 1.3 OID Management Integration
- **Current**: `lib/snmp_mgr/oid.ex` custom OID handling
- **Target**: Leverage `SnmpLib.OID` for enhanced OID operations
- **Tasks**:
  - Replace custom OID parsing with `SnmpLib.OID.parse/1`
  - Use `SnmpLib.OID.to_string/1` and `SnmpLib.OID.to_list/1`
  - Integrate MIB-based OID resolution from `SnmpLib.MIB`
  - Add OID validation using `SnmpLib.OID.valid?/1`

### Phase 2: Advanced Features and Error Handling (Week 2)
**Goal**: Integrate advanced snmp_lib features and improve error handling

#### 2.1 Error Handling Standardization  
- **Current**: Custom error atoms and tuples
- **Target**: `SnmpLib.Error` structured error handling
- **Tasks**:
  - Create error mapping layer between custom and snmp_lib errors
  - Update all error returns to include structured error information
  - Implement `SnmpLib.ErrorHandler` for consistent retry logic
  - Add error categorization (network, protocol, application)

#### 2.2 MIB Integration
- **Current**: `lib/snmp_mgr/mib.ex` basic MIB support
- **Target**: Full `SnmpLib.MIB` integration
- **Tasks**:
  - Replace custom MIB parsing with `SnmpLib.MIB.Parser`
  - Integrate MIB loading with `SnmpLib.MIB.Loader`
  - Add OID-to-name resolution using loaded MIBs
  - Support standard MIB modules (RFC1213-MIB, IF-MIB, etc.)

#### 2.3 Transport Layer Enhancement
- **Current**: Basic UDP transport
- **Target**: `SnmpLib.Transport` with multiple transport options
- **Tasks**:
  - Replace direct UDP calls with `SnmpLib.Transport.UDP`
  - Add support for `SnmpLib.Transport.TCP` (future-proofing)
  - Implement proper connection pooling using `SnmpLib.Pool`
  - Add transport-level metrics and monitoring

### Phase 3: Performance and Scalability (Week 3)
**Goal**: Leverage snmp_lib's performance features and connection management

#### 3.1 Connection Pool Integration
- **Current**: `lib/snmp_mgr/pool.ex` custom pooling
- **Target**: `SnmpLib.Pool` with advanced features
- **Tasks**:
  - Replace custom pool implementation with `SnmpLib.Pool`
  - Configure connection lifecycle management
  - Implement health checking for pooled connections
  - Add pool metrics and monitoring dashboards

#### 3.2 Bulk Operations Optimization
- **Current**: `lib/snmp_mgr/bulk.ex` custom bulk implementation
- **Target**: `SnmpLib.Bulk` with optimized batching
- **Tasks**:
  - Replace custom bulk operations with `SnmpLib.Bulk`
  - Implement intelligent batch sizing based on target capabilities
  - Add bulk operation retry logic with exponential backoff
  - Optimize memory usage for large bulk responses

#### 3.3 Walker Enhancement
- **Current**: `lib/snmp_mgr/walk.ex` basic table walking
- **Target**: `SnmpLib.Walker` with advanced features
- **Tasks**:
  - Replace custom walker with `SnmpLib.Walker`
  - Add adaptive bulk sizing for optimal performance
  - Implement concurrent walking for multiple tables
  - Add walk progress monitoring and cancellation

### Phase 4: Monitoring and Management (Week 4)
**Goal**: Integrate snmp_lib's monitoring and management capabilities

#### 4.1 Metrics Integration
- **Current**: `lib/snmp_mgr/metrics.ex` basic metrics
- **Target**: `SnmpLib.Monitor` comprehensive monitoring
- **Tasks**:
  - Replace custom metrics with `SnmpLib.Monitor`
  - Integrate with `SnmpLib.Dashboard` for web-based monitoring
  - Add performance trending and alerting
  - Export metrics to external systems (Prometheus, etc.)

#### 4.2 Configuration Management
- **Current**: `lib/snmp_mgr/config.ex` basic configuration
- **Target**: `SnmpLib.Config` with validation and hot-reload
- **Tasks**:
  - Migrate configuration to `SnmpLib.Config` format
  - Add configuration validation using schemas
  - Implement hot configuration reloading
  - Support environment-specific configurations

#### 4.3 Security Enhancement
- **Target**: `SnmpLib.Security` for SNMPv3 preparation
- **Tasks**:
  - Integrate `SnmpLib.Security.USM` for user-based security
  - Add authentication and privacy support preparation
  - Implement secure credential management
  - Add security audit logging

### Phase 5: Testing and Validation (Week 5)
**Goal**: Comprehensive testing and validation of migrated functionality

#### 5.1 Test Suite Migration
- **Current**: Custom test assertions and mocking
- **Target**: Tests using snmp_lib test utilities
- **Tasks**:
  - Update test fixtures to use `SnmpLib.TestSupport`
  - Migrate simulator integration to work with snmp_lib
  - Add comprehensive integration tests
  - Validate RFC compliance using snmp_lib's compliance tools

#### 5.2 Performance Validation
- **Tasks**:
  - Benchmark migrated operations against original implementation
  - Validate memory usage improvements
  - Test scalability with large numbers of concurrent operations
  - Measure and optimize latency characteristics

#### 5.3 Backward Compatibility Validation
- **Tasks**:
  - Ensure all existing APIs continue to work
  - Validate error message compatibility for client applications
  - Test migration path for existing deployments
  - Document any breaking changes and migration steps

## Implementation Guidelines

### Code Organization
```
lib/snmp_mgr/
├── adapters/           # Compatibility layers
│   ├── pdu_adapter.ex
│   ├── error_adapter.ex
│   └── config_adapter.ex
├── legacy/             # Original implementations (deprecated)
└── snmp_lib/          # snmp_lib integrations
    ├── client.ex      # Main client interface
    ├── pool_manager.ex
    └── monitor.ex
```

### Error Handling Strategy
- Maintain existing error signatures for backward compatibility
- Add structured error information using `SnmpLib.Error`
- Implement error categorization for better debugging
- Add error context preservation across layer boundaries

### Testing Strategy
- Maintain existing test structure and assertions
- Add snmp_lib-specific test cases
- Use `SnmpLib.TestSupport` for realistic SNMP simulation
- Implement regression testing to ensure no functionality loss

### Performance Monitoring
- Track migration impact on key performance metrics
- Monitor memory usage during bulk operations
- Measure latency improvements from connection pooling
- Validate scalability improvements

## Risk Mitigation

### Technical Risks
1. **Breaking Changes**: Maintain adapter layers for smooth migration
2. **Performance Regression**: Comprehensive benchmarking at each phase
3. **Feature Loss**: Detailed feature mapping and validation
4. **Integration Issues**: Incremental migration with rollback capability

### Migration Risks
1. **Timeline Pressure**: Phased approach allows for adjustment
2. **Resource Conflicts**: Clear separation of old and new implementations
3. **Testing Gaps**: Comprehensive test coverage validation
4. **Documentation Debt**: Document changes at each phase

## Success Criteria

### Technical Success
- [ ] All existing functionality preserved
- [ ] Performance equal or better than original
- [ ] Memory usage optimized
- [ ] Error handling improved
- [ ] RFC compliance enhanced

### Quality Success
- [ ] Test coverage maintained or improved
- [ ] Code complexity reduced
- [ ] Documentation updated
- [ ] Security posture improved
- [ ] Monitoring capabilities enhanced

## Rollback Plan
- Each phase creates tagged commits for rollback points
- Adapter pattern allows gradual feature switching
- Feature flags enable runtime switching between implementations
- Comprehensive testing validates rollback procedures

## Post-Migration Benefits
1. **Standardization**: Using established, tested SNMP library
2. **RFC Compliance**: Better adherence to SNMP standards
3. **Performance**: Optimized connection pooling and bulk operations
4. **Maintainability**: Reduced custom code, better error handling
5. **Features**: Access to advanced snmp_lib capabilities
6. **Security**: Foundation for SNMPv3 implementation
7. **Monitoring**: Enhanced observability and debugging capabilities

---
*Migration Plan Created: June 3, 2025*
*Target Completion: July 8, 2025 (5 weeks)*
*snmp_lib Version: v0.2.0*

## Progress Update - June 3, 2025

### ✅ Phase 1.1 Completed - PDU Module Migration
- **Time**: ~30 minutes 
- **Approach**: Direct replacement instead of adapter pattern
- **Result**: 
  - Custom PDU module completely removed
  - All calls migrated to `SnmpLib.PDU`
  - 7 PDU-specific test files removed (tested in snmp_lib)
  - Tests compile and run: 49 tests, 3 failures
  - Failures are now real integration issues, not PDU-related

### Next Steps: Phase 1.2 - Core Operations Update
- Fix remaining 3 test failures (likely error handling/type differences)
- Begin migration of core operations to use `SnmpLib.Client`