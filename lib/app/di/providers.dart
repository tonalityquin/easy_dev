import 'package:provider/single_child_widget.dart';
import 'repositories.dart';
import 'states.dart';

final List<SingleChildWidget> appProviders = [
  ...repositoryProviders,
  ...stateProviders,
];
