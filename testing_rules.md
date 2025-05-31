  🎯 ESSENTIAL TESTING RULES

  1. ALL TESTS MUST USE SNMPSimulator - Never hardcode "127.0.0.1" or real hosts
  2. ALL TIMEOUTS MUST BE SHORT - Use 200ms max, all tests are local
  3. FOLLOW EXISTING PATTERNS - If bulk_operations_test.exs already uses simulator correctly, don't touch it
  4. TEST FIRST - Check current status before making changes
  5. SIMULATOR SETUP - Always use SNMPSimulator.create_test_device() and device.community