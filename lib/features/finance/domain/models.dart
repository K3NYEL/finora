class Account {
  final int id;
  final String name, type;
  final double balance;
  const Account(this.id, this.name, this.type, this.balance);
}

class Category {
  final int id;
  final String name;
  const Category(this.id, this.name);
}

class Movement {
  final String kind, title, subtitle, date;
  final double amount;
  const Movement(this.kind, this.title, this.subtitle, this.amount, this.date);
}

class Summary {
  final double income, expense;
  const Summary(this.income, this.expense);
  double get balance => income - expense;
}
