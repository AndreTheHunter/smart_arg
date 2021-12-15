import 'boolean_argument.dart';

class HelpArgument extends BooleanArgument {
  const HelpArgument({bool? isOption})
      : super(
          short: 'h',
          help: 'Show help',
          isOption: isOption,
        );

  @override
  List<String> specialKeys(String? short, String? long) {
    return ['-?'];
  }
}
