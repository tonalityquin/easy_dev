import 'package:provider/single_child_widget.dart';
import 'repositories.dart';
import 'states.dart';

// 전체 Providers 리스트
final List<SingleChildWidget> appProviders = [
  ...repositoryProviders,
  ...stateProviders,
];
