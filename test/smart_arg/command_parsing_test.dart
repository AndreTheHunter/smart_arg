import 'package:smart_arg/smart_arg.dart';
import 'package:test/test.dart';

import '../smart_arg_test.reflectable.dart';

String? whatExecuted;

@SmartArg.reflectable
@Parser(exitOnFailure: false, description: 'put command')
class PutCommand extends SmartArgCommand {
  @StringArgument()
  String? filename;

  @override
  void execute(SmartArg parentArguments) {
    whatExecuted = 'put-command: $filename';
  }
}

@SmartArg.reflectable
@Parser(exitOnFailure: false, description: 'get command')
class GetCommand extends SmartArgCommand {
  @StringArgument()
  String? filename;

  @override
  void execute(SmartArg parentArguments) {
    whatExecuted = 'get-command: $filename';
  }
}

@SmartArg.reflectable
@Parser(exitOnFailure: false)
class TestSimpleCommand extends SmartArg {
  @BooleanArgument(short: 'v')
  bool? verbose;

  @Command(help: 'Put a file on a remote host')
  PutCommand? put;

  @Command(help: 'Get a file from a remote host')
  GetCommand? get;

  List<String> hookOrder = [];

  @override
  void beforeCommandParse(SmartArgCommand command, List<String> arguments) {
    super.beforeCommandParse(command, arguments);
    hookOrder.add("beforeCommandParse");
  }

  @override
  void beforeCommandExecute(SmartArgCommand command) {
    super.beforeCommandExecute(command);
    hookOrder.add("beforeCommandExecute");
  }

  @override
  void afterCommandExecute(SmartArgCommand command) {
    super.afterCommandExecute(command);
    hookOrder.add("afterCommandExecute");
  }
}

List<String> subcommandHookOrder = [];

@SmartArg.reflectable
@Parser(exitOnFailure: false, description: 'The Child Command')
class ChildCommand extends SmartArgCommand {
  @StringArgument()
  String? aValue;

  @Command()
  late ChildCommand child;

  @override
  void execute(SmartArg parentArguments) {
    whatExecuted = 'ChildCommand: $aValue';
    subcommandHookOrder.add("ChildExecute");
  }

  @override
  void beforeCommandParse(SmartArgCommand command, List<String> arguments) {
    super.beforeCommandParse(command, arguments);
    subcommandHookOrder.add("beforeChildParse");
  }

  @override
  void beforeCommandExecute(SmartArgCommand command) {
    super.beforeCommandExecute(command);
    subcommandHookOrder.add("beforeChildExecute");
  }

  @override
  void afterCommandExecute(SmartArgCommand command) {
    super.afterCommandExecute(command);
    subcommandHookOrder.add("afterChildExecute");
  }
}

@SmartArg.reflectable
@Parser(exitOnFailure: false, description: 'The Father Command')
class FatherCommand extends SmartArgCommand {
  @StringArgument()
  String? aValue;

  @Command()
  late ChildCommand child;

  @override
  void execute(SmartArg parentArguments) {
    whatExecuted = 'FatherCommand: $aValue';
    subcommandHookOrder.add("FatherExecute");
  }

  @override
  void beforeCommandParse(SmartArgCommand command, List<String> arguments) {
    super.beforeCommandParse(command, arguments);
    subcommandHookOrder.add("beforeFatherParse");
  }

  @override
  void beforeCommandExecute(SmartArgCommand command) {
    super.beforeCommandExecute(command);
    subcommandHookOrder.add("beforeFatherExecute");
  }

  @override
  void afterCommandExecute(SmartArgCommand command) {
    super.afterCommandExecute(command);
    subcommandHookOrder.add("afterFatherExecute");
  }
}

@SmartArg.reflectable
@Parser(exitOnFailure: false, description: 'The Parent Command')
class GrandFatherCommand extends SmartArg {
  @Command()
  late ChildCommand child;

  @Command()
  late FatherCommand father;

  @StringArgument()
  String? aValue;

  @override
  void beforeCommandParse(SmartArgCommand command, List<String> arguments) {
    super.beforeCommandParse(command, arguments);
    subcommandHookOrder.add("beforeGrandFatherParse");
  }

  @override
  void beforeCommandExecute(SmartArgCommand command) {
    super.beforeCommandExecute(command);
    subcommandHookOrder.add("beforeGrandFatherExecute");
  }

  @override
  void afterCommandExecute(SmartArgCommand command) {
    super.afterCommandExecute(command);
    subcommandHookOrder.add("afterGrandFatherExecute");
  }
}

void main() {
  initializeReflectable();

  group('parsing', () {
    group('commands', () {
      setUp(() {
        whatExecuted = null;
      });

      test('calls hooks', () {
        var cmd = TestSimpleCommand();
        final args = cmd..parse(['get', '--filename=download.txt']);
        expect(args.verbose, null);
        expect(whatExecuted, 'get-command: download.txt');
        expect(cmd.hookOrder, [
          "beforeCommandParse",
          "beforeCommandExecute",
          "afterCommandExecute"
        ]);
      });

      test('executes with no arguments', () {
        final args = TestSimpleCommand()..parse([]);
        expect(args.verbose, null);
      });

      test('executes with a command', () {
        final args = TestSimpleCommand()
          ..parse(['-v', 'put', '--filename=upload.txt']);
        expect(args.verbose, true);
        expect(whatExecuted, 'put-command: upload.txt');
      });

      test('executes with another command', () {
        final args = TestSimpleCommand()
          ..parse(['-v', 'get', '--filename=download.txt']);
        expect(args.verbose, true);
        expect(whatExecuted, 'get-command: download.txt');
      });

      test('help appears', () {
        final args = TestSimpleCommand();
        final help = args.usage();

        expect(help.contains('COMMANDS'), true);
        expect(help.contains('  get'), true);
        expect(help.contains('  put'), true);
        expect(help.contains('Get a file'), true);
        expect(help.contains('Put a file'), true);
      });
    });

    group('subcommands', () {
      setUp(() {
        whatExecuted = null;
        subcommandHookOrder = [];
      });

      test('First Subcommand', () {
        GrandFatherCommand().parse(['father', '--a-value=beta']);
        expect(whatExecuted, 'FatherCommand: beta');
        expect(subcommandHookOrder, [
          'beforeGrandFatherParse',
          'beforeGrandFatherExecute',
          'FatherExecute',
          'afterGrandFatherExecute'
        ]);
      });

      test('Second subcommand', () {
        GrandFatherCommand().parse(['father', 'child', '--a-value=charlie']);
        expect(whatExecuted, 'ChildCommand: charlie');
        expect(subcommandHookOrder, [
          'beforeGrandFatherParse',
          'beforeFatherParse',
          'beforeGrandFatherExecute',
          'beforeFatherExecute',
          'ChildExecute',
          'afterFatherExecute',
          'afterGrandFatherExecute'
        ]);
      });

      test('Triply Nested subcommand', () {
        GrandFatherCommand()
            .parse(['father', 'child', 'child', '--a-value=delta']);
        expect(whatExecuted, 'ChildCommand: delta');
        expect(subcommandHookOrder, [
          'beforeGrandFatherParse',
          'beforeFatherParse',
          'beforeChildParse',
          'beforeGrandFatherExecute',
          'beforeFatherExecute',
          'beforeChildExecute',
          'ChildExecute',
          'afterChildExecute',
          'afterFatherExecute',
          'afterGrandFatherExecute'
        ]);
      });
    });
  });
}
