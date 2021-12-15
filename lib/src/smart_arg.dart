import 'dart:io';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:reflectable/reflectable.dart';

import 'argument.dart';
import 'command.dart';
import 'group.dart';
import 'help_argument.dart';
import 'mirror_argument_pair.dart';
import 'parser.dart';
import 'predicates.dart';
import 'reflector.dart';
import 'smart_arg_command.dart';
import 'string_utils.dart';
import 'usage.dart' as u;

class ParsedResult {
  final MirrorParameterPair? command;
  final List<String>? commandArguments;
  final bool success;

  const ParsedResult({this.command, this.commandArguments}) : success = true;

  const ParsedResult.success()
      : success = true,
        command = null,
        commandArguments = null;

  const ParsedResult.failure()
      : success = false,
        command = null,
        commandArguments = null;
}

bool _wasSetInParent(final SmartArg command, final String argument) {
  bool wasSet = false;
  if (isNotNull(command.parent)) {
    final SmartArg parent = command.parent!;
    wasSet = parent._wasSet.contains(argument);
    if (isFalse(wasSet)) {
      return _wasSetInParent(parent, argument);
    }
  }
  return wasSet;
}

// Local type is needed for strict type checking in lists.
// var abc = [] turns out to be a List<dynamic> which is not
// as safe as List<String> abc = [] for example.
//
// This file uses a lot of lists, therefore the
// omit_local_variable_types linting rule is disabled globally
// for this file.
//
// ignore_for_file: omit_local_variable_types

/// Base class for the [SmartArg] parser.
///
/// Your application should extend [SmartArg], add public properties,
/// and call the [SmartArg.parse()] method on your class.
class SmartArg {
  static const reflectable = Reflector.reflector;

  //
  // Public API
  //

  /// List of extras supplied on the command line.
  ///
  /// Extras are anything supplied on the command line that was not an option.
  List<String>? get extras => _extras;

  /// The environment for [SmartArg] as a map from string key to string value.
  ///
  /// The map is unmodifiable, and its content is retrieved from the operating
  /// system [Platform.environment] on unless provided otherwise.
  late Map<String, String> _environment = Platform.environment;

  /// The Parent [SmartArg], or [SmartArgCommand] instance for the current
  /// subcommand.
  SmartArg? parent;

  /// Recursively walks the [classMirror] and it's associated
  /// [ClassMirror.superclass] (and subsequently declared [mixin]s) to find all
  /// public [VariableMirror] declarations
  List<DeclarationMirror> _walkDeclarations(ClassMirror classMirror) {
    ClassMirror? superMirror;
    try {
      superMirror = classMirror.superclass;
    } on NoSuchCapabilityError catch (_) {
      // A NoSuchCapabilityError is thrown when the superclass not annotated
      // with @SmartArg.reflectable
    }
    List<DeclarationMirror> mirrors = [];
    if (isNotNull(superMirror)) {
      mirrors = _walkDeclarations(superMirror!);
    }
    var classVals = classMirror.declarations.values;
    return [classVals, mirrors]
        .expand((e) => e)
        .where((p) => p is VariableMirror && isFalse(p.isPrivate))
        .toList();
  }

  SmartArg() {
    final instanceMirror = reflectable.reflect(this);

    // Find our app meta data (if any)
    _app =
        instanceMirror.type.metadata.firstWhere((m) => m is Parser) as Parser?;

    // Build an easy to use lookup for arguments on the command line
    // to their corresponding Parameter configurations.
    _values = {};
    _commands = {};
    _mirrorParameterPairs = [];

    {
      Group? currentGroup;
      for (final mirror in _walkDeclarations(instanceMirror.type)) {
        currentGroup =
            mirror.metadata.firstWhereOrNull((m) => m is Group) as Group? ??
                currentGroup;

        final parameter =
            mirror.metadata.firstWhereOrNull((m) => m is Argument);
        if (parameter != null) {
          final mpp = MirrorParameterPair(
            mirror as VariableMirror,
            parameter as Argument,
            currentGroup,
          );
          for (final key in mpp.keys(_app)) {
            if (_values.containsKey(key)) {
              throw StateError('$key was configured multiple times');
            }
            _values[key] = mpp;
          }
          _mirrorParameterPairs.add(mpp);
          if (parameter is Command) {
            _commands[mpp.displayKey] = mpp;
          }
        }
      }
    }
  }

  /// Parse the [arguments] list populating properties on the [SmartArg] class.
  ///
  /// If [Parser.exitOnFailure] is set to true, this function will call
  /// `exit(1)` if there is a command line parsing error. It will do so only
  /// after telling the user what the error was and displaying the result of
  /// [usage()].
  void parse(List<String> arguments) {
    _resetParser();

    try {
      final ParsedResult result = _parse(arguments);
      if (isNotNull(result.command)) {
        _launchCommand(result.command!, result.commandArguments ?? []);
      } else if (result.success) {
        _validate();
      }
    } on ArgumentError catch (e) {
      if (isTrue(_app?.exitOnFailure)) {
        print(e.toString());
        print('');
        print(usage());
        exit(1);
      }

      rethrow;
    }
  }

  /// Return a string telling the user how to use your application from the command line.
  String usage() {
    List<String?> usageLines = [];
    const lineIndent = 2;
    const lineWidth = 80 - lineIndent;
    final linePrefix = ' ' * lineIndent;
    const optionColumnWidth = 25;
    const helpLineWidth = lineWidth - optionColumnWidth;

    final arguments = _mirrorParameterPairs.where(
      (mpp) =>
          isFalse(mpp.argument is Command) && mpp.argument.isOption != true,
    );

    if (isNotNull(_app?.description)) {
      usageLines.add(_app!.description);
      usageLines.add('');
    }

    usageLines
      ..addAll(
        u.arguments(
          _app,
          arguments,
          helpLineWidth: helpLineWidth,
          optionColumnWidth: optionColumnWidth,
          linePrefix: linePrefix,
          lineIndent: lineIndent,
          lineWidth: lineWidth,
        ),
      )
      ..addAll(
        u.commands(
          _mirrorParameterPairs.where((v) => v.argument is Command),
          helpLineWidth: helpLineWidth,
          optionColumnWidth: optionColumnWidth,
          linePrefix: linePrefix,
        ),
      )
      ..addAll(
        u.options(
          _app,
          _mirrorParameterPairs.where((mpp) => mpp.argument.isOption == true),
          helpLineWidth: helpLineWidth,
          optionColumnWidth: optionColumnWidth,
          linePrefix: linePrefix,
        ),
      );

    if (isNotNull(_app?.extendedHelp)) {
      for (final eh in _app!.extendedHelp!) {
        if (isNull(eh.help)) {
          throw StateError('Help.help must be set');
        }

        usageLines.add('');

        if (isNotNull(eh.header)) {
          usageLines.add(hardWrap(eh.header!, lineWidth));
          usageLines.add(
            indent(hardWrap(eh.help!, lineWidth - lineIndent), lineIndent),
          );
        } else {
          usageLines.add(hardWrap(eh.help!, lineWidth));
        }
      }
    }

    return u.removeConsecutiveBlanks(usageLines).join('\n');
  }

  //
  // Private API
  //

  Parser? _app;
  late Map<String?, MirrorParameterPair> _values;
  late Map<String?, MirrorParameterPair> _commands;
  List<String>? _extras;
  late Set<String?> _wasSet;

  // tracked so we can have a proper order for help output
  late List<MirrorParameterPair> _mirrorParameterPairs;

  bool _isStacked(String value) {
    final isSingleDash = value.startsWith('-') && !value.startsWith('--');
    final isLongerThanShort = value.length > 2;
    final isAssignment = isLongerThanShort && value.substring(2, 3) == '=';

    return isSingleDash && !isAssignment && isLongerThanShort;
  }

  List<String> _rewriteArguments(List<String> arguments) {
    List<String> result = [];
    for (final arg in arguments) {
      if (_isStacked(arg)) {
        final individualArgs = arg.split('').skip(1).map((v) => '-$v').toList();

        result.addAll(individualArgs);
      } else {
        result.add(arg);
      }
    }

    return result;
  }

  ParsedResult _parse(List<String> arguments) {
    final instanceMirror = reflectable.reflect(this);
    final List<String> expandedArguments = _rewriteArguments(arguments);
    ParsedResult? commandResult;

    int argumentIndex = 0;
    while (argumentIndex < expandedArguments.length) {
      var argument = expandedArguments[argumentIndex];
      var originalArgument = argument;

      argumentIndex++;

      if (isNull(commandResult)) {
        if (argument.toLowerCase() == _app!.argumentTerminator?.toLowerCase()) {
          _extras!.addAll(expandedArguments.skip(argumentIndex));
          return ParsedResult.success();
        } else if (isFalse(argument.startsWith('-'))) {
          if (_commands.containsKey(argument)) {
            //The argument is actually a command
            final command = _commands[argument]!;
            final commandArguments = arguments.skip(argumentIndex).toList();
            commandResult = ParsedResult(
              command: command,
              commandArguments: commandArguments,
            );
            continue;
          } else {
            // Was not an argument, must be an extra
            _extras!.add(argument);
            if (isFalse(_app!.allowTrailingArguments)) {
              _extras!.addAll(expandedArguments.skip(argumentIndex));
              return ParsedResult.success();
            }
            continue;
          }
        }
      } else {
        if (_commands.containsKey(argument)) {
          //Skip if the argument is another subcommand
          continue;
        }
      }

      var argumentParts = argument.split('=');
      var argumentName = argumentParts.first;
      var hasValueViaEqual = argumentParts.length > 1;
      dynamic value = argumentParts.skip(1).join('=');

      if (argumentName.startsWith('--')) {
        argumentName = argumentName.substring(2);
      }

      // Find our argument configuration
      var argumentConfiguration = _values[argumentName];
      if (isNull(commandResult) &&
          isNull(argumentConfiguration) &&
          isFalse(_wasSetInParent(this, argumentName))) {
        throw ArgumentError('$originalArgument is invalid');
      } else if (isNotNull(argumentConfiguration)) {
        if (argumentConfiguration!.argument.needsValue &&
            isFalse(hasValueViaEqual)) {
          if (argumentIndex >= expandedArguments.length) {
            throw ArgumentError(
              '${argumentConfiguration.displayKey} expects a value but none was supplied.',
            );
          }

          value = expandedArguments[argumentIndex];
          argumentIndex++;
        }

        if (isNull(commandResult) ||
            isTrue(argumentConfiguration.argument.isOption)) {
          _trySetValue(instanceMirror, argumentName, value);
        }

        if (isNull(commandResult) &&
            argumentConfiguration.argument is HelpArgument) {
          _extras!.addAll(expandedArguments.skip(argumentIndex));
          return ParsedResult.failure();
        }
      }
    }
    return commandResult ?? ParsedResult.success();
  }

  //Attempts to set the value of the argument
  void _trySetValue(
    InstanceMirror instanceMirror,
    String? argumentName,
    dynamic value,
  ) {
    var argumentConfiguration = _values[argumentName]!;
    value = argumentConfiguration.argument.handleValue(argumentName, value);

    // Try setting it as a list first
    dynamic instanceValue;
    try {
      instanceValue =
          instanceMirror.invokeGetter(argumentConfiguration.mirror.simpleName);
    } catch (error) {
      if (error.runtimeType.toString() != 'LateError') {
        rethrow;
      }
    }

    // There is no way of determining if a class variable is a list or not through
    // introspection, therefore we try to add the value as a list, or append to the
    // list first. If that fails, we assume it is not a list :-/
    if (isNull(instanceValue)) {
      try {
        instanceValue = (argumentConfiguration.argument as dynamic).emptyList;
        (instanceValue as List).add(value);

        instanceMirror.invokeSetter(
          argumentConfiguration.mirror.simpleName,
          instanceValue,
        );
        _wasSet.add(argumentConfiguration.displayKey);
      } catch (_) {
        // Adding as a list failed, so it must not be a list. Let's set it
        // as a normal value.
        instanceMirror.invokeSetter(
          argumentConfiguration.mirror.simpleName,
          value,
        );
        _wasSet.add(argumentConfiguration.displayKey);
      }
    } else {
      try {
        // Since we can not determine if the instanceValue is a list or not...
        //
        // Just try the .first method to see if it exists. We don't really care
        // about the value, we just want to execute at least two methods on
        // the instance value to do as good of a job as we can to determine if
        // the type is a List or not.
        //
        // .first is the first method, .add will be the second
        var _ = (instanceValue as List).first;
        instanceValue.add(value);
        _wasSet.add(argumentConfiguration.displayKey);
      } catch (_) {
        if (_wasSet.contains(argumentConfiguration.displayKey)) {
          throw ArgumentError(
            '${argumentConfiguration.displayKey} was supplied more than once',
          );
        }

        // Adding as a list failed, so it must not be a list. Let's set it
        // as a normal value.
        instanceMirror.invokeSetter(
          argumentConfiguration.mirror.simpleName,
          value,
        );
        _wasSet.add(argumentConfiguration.displayKey);
      }
    }
  }

  bool _argumentWasSet(String? argumentName) {
    return _wasSet.contains(argumentName);
  }

  void _validate() {
    // Check to see if we have any required arguments missing
    final List<String?> isMissing = [];
    final instanceMirror = reflectable.reflect(this);

    for (var mpp in _mirrorParameterPairs) {
      var argumentName = mpp.displayKey;
      final String? envVar = mpp.argument.environmentVariable;
      if (isFalse(_argumentWasSet(argumentName)) && isNotBlank(envVar)) {
        String? envVarValue = _environment[envVar];
        if (isNotBlank(envVarValue)) {
          _trySetValue(instanceMirror, argumentName, envVarValue!.trim());
        }
      }

      if (isTrue(mpp.argument.isRequired) &&
          isFalse(_argumentWasSet(argumentName))) {
        isMissing.add(mpp.displayKey);
      }
    }

    if (isMissing.isNotEmpty) {
      throw ArgumentError(
        'missing required arguments: ${isMissing.join(', ')}',
      );
    }

    if (isNotNull(_app!.minimumExtras) &&
        extras!.length < _app!.minimumExtras!) {
      throw ArgumentError(
        'expecting at least ${_app!.minimumExtras} free form arguments but ${extras!.length} was supplied',
      );
    } else if (isNotNull(_app!.maximumExtras) &&
        extras!.length > _app!.maximumExtras!) {
      throw ArgumentError(
        'expecting at most ${_app!.maximumExtras} free form arguments but ${extras!.length} was supplied',
      );
    }
  }

  void _launchCommand(MirrorParameterPair commandMpp, List<String> arguments) {
    final a = commandMpp.mirror;
    final b = a.type as ClassMirror;
    final command = b.newInstance('', []) as SmartArgCommand;
    command.parent = this;
    final subcommands = command._commands;

    beforeCommandParse(command, arguments);
    command.parse(arguments);

    if (arguments.isEmpty ||
        isFalse(subcommands.containsKey(arguments.first))) {
      beforeCommandExecute(command);
      command.execute(this);
    }

    afterCommandExecute(command);
  }

  void _resetParser() {
    _wasSet = {};
    _extras = [];
  }

  /// Sets the environment map to be used during argument parsing
  void withEnvironment(Map<String, String> environment) {
    _environment = environment;
  }

  /// Invoked before a command is parsed
  void beforeCommandParse(SmartArgCommand command, List<String> arguments) {}

  /// Invoked before a command is executed
  void beforeCommandExecute(SmartArgCommand command) {
    if (this is SmartArgCommand) {
      parent?.beforeCommandExecute(this as SmartArgCommand);
    }
  }

  /// Invoked after a command is executed
  void afterCommandExecute(SmartArgCommand command) {}
}
