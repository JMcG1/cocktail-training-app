class WorkspaceTabHistory {
  WorkspaceTabHistory({required int initialIndex})
    : _stack = <int>[initialIndex];

  final List<int> _stack;

  int get currentIndex => _stack.last;

  void visit(int index) {
    if (_stack.isNotEmpty && _stack.last == index) {
      return;
    }
    _stack.add(index);
  }

  int? popPrevious() {
    if (_stack.length < 2) {
      return null;
    }
    _stack.removeLast();
    return _stack.last;
  }

  void syncFromBrowser(int index) {
    if (index == currentIndex) {
      return;
    }
    if (_stack.length > 1 && _stack[_stack.length - 2] == index) {
      _stack.removeLast();
      return;
    }
    visit(index);
  }

  List<int> get debugStack => List.unmodifiable(_stack);
}
