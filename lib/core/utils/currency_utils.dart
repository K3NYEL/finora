import 'package:intl/intl.dart';

final _f = NumberFormat('#,##0.##');
String money(double v) => r'RD$ ' + _f.format(v);
