import 'package:flutter_test/flutter_test.dart';
import 'package:z1_engine/core/services/so_binary_hardening_service.dart';

void main() {
  final service = SoBinaryHardeningService();

  test('parses ELF compatibility and hardening properties', () async {
    const output = '''
ELF Header:
  Class:                             ELF64
  Data:                              2's complement, little endian
  Type:                              DYN (Shared object file)
  Machine:                           AArch64
Program Headers:
  GNU_STACK      0x000000 0x000000 0x000000 0x000000 0x000000 RW  0x10
  GNU_RELRO      0x001000 0x001000 0x001000 0x000100 0x000100 R   0x1
Dynamic section:
  0x0000000000000001 (NEEDED) Shared library: [liblog.so]
  0x000000000000000e (SONAME) Library soname: [libsample.so]
  0x000000000000001e (FLAGS) BIND_NOW
Symbol table '.dynsym':
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     1: 0000000000001000    24 FUNC    GLOBAL DEFAULT    7 Java_demo_run
     2: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND malloc
''';

    final snapshot = await service.inspectForTesting(output);

    expect(snapshot.elfClass, 'ELF64');
    expect(snapshot.machine, 'AArch64');
    expect(snapshot.soname, 'libsample.so');
    expect(snapshot.neededLibraries, {'liblog.so'});
    expect(snapshot.exportedSymbols, {'Java_demo_run'});
    expect(snapshot.hasRelro, isTrue);
    expect(snapshot.hasNonExecutableStack, isTrue);
    expect(snapshot.bindNow, isTrue);
    expect(snapshot.hasTextRelocations, isFalse);
  });

  test('detects exported symbol compatibility changes', () async {
    const base = '''
ELF Header:
  Class: ELF64
  Data: little endian
  Type: DYN
  Machine: AArch64
Symbol table '.dynsym':
  1: 00000001 4 FUNC GLOBAL DEFAULT 7 exported_one
''';
    const changed = '''
ELF Header:
  Class: ELF64
  Data: little endian
  Type: DYN
  Machine: AArch64
Symbol table '.dynsym':
  1: 00000001 4 FUNC GLOBAL DEFAULT 7 exported_two
''';

    final before = await service.inspectForTesting(base);
    final after = await service.inspectForTesting(changed);

    expect(before.compatibilityDifference(after), '动态导出符号');
  });
}
