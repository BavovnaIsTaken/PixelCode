import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/agent_id_format.dart';

void main() {
  group('agentRoleOf', () {
    test('strips #N suffix', () {
      expect(agentRoleOf('tech-lead#1'), 'tech-lead');
      expect(agentRoleOf('coder#42'), 'coder');
      expect(agentRoleOf('ui-ux-designer#3'), 'ui-ux-designer');
    });

    test('returns input unchanged when no suffix', () {
      expect(agentRoleOf('manager'), 'manager');
      expect(agentRoleOf('tech-lead'), 'tech-lead');
    });

    test('handles empty string', () {
      expect(agentRoleOf(''), '');
    });

    test('leading # is preserved (no role present)', () {
      // indexOf returns 0; substring(0,0) would yield empty role. We instead
      // require hash > 0 so the input is returned as-is.
      expect(agentRoleOf('#1'), '#1');
    });
  });

  group('agentInstanceSuffixOf', () {
    test('returns #N suffix', () {
      expect(agentInstanceSuffixOf('tech-lead#1'), '#1');
      expect(agentInstanceSuffixOf('coder#42'), '#42');
    });

    test('returns empty when no suffix', () {
      expect(agentInstanceSuffixOf('manager'), '');
      expect(agentInstanceSuffixOf(''), '');
    });
  });

  group('shortAgentLabel', () {
    test('maps known roles to short form with suffix', () {
      expect(shortAgentLabel('tech-lead#1'), 'TL#1');
      expect(shortAgentLabel('coder#2'), 'DEV#2');
      expect(shortAgentLabel('manager#1'), 'MGR#1');
      expect(shortAgentLabel('reviewer#1'), 'REV#1');
      expect(shortAgentLabel('tester#1'), 'QA#1');
      expect(shortAgentLabel('security#1'), 'SEC#1');
      expect(shortAgentLabel('ui-ux-designer#1'), 'UI#1');
      expect(shortAgentLabel('llm-specialist#1'), 'LLM#1');
      expect(shortAgentLabel('character-artist#1'), 'ART#1');
    });

    test('maps known roles to short form without suffix', () {
      expect(shortAgentLabel('tech-lead'), 'TL');
      expect(shortAgentLabel('coder'), 'DEV');
    });

    test('unknown role passes through with suffix', () {
      expect(shortAgentLabel('foo#1'), 'foo#1');
      expect(shortAgentLabel('foo'), 'foo');
    });
  });
}
