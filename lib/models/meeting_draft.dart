class DraftStudent {
  final String name, reg, tech;
  DraftStudent(this.name, this.reg, this.tech);
  DraftStudent copy() => DraftStudent(name, reg, tech);
}

int _nextUid = 0;

class DraftGroup {
  final int uid;
  final String project, supervisor;
  final List<DraftStudent> students;
  DraftGroup({
    int? uid,
    required this.project,
    required this.supervisor,
    required List<DraftStudent> students,
  }) : uid = uid ?? _nextUid++,
       students = List.unmodifiable(students);

  DraftGroup copy() => DraftGroup(
    uid: uid,
    project: project,
    supervisor: supervisor,
    students: students.map((s) => s.copy()).toList(),
  );
}

class LockedGroup {
  final int no, time;
  final String status, project, supervisor;
  final List<DraftStudent> students;
  LockedGroup({
    required this.no,
    required this.time,
    required this.status,
    required this.project,
    required this.supervisor,
    required List<DraftStudent> students,
  }) : students = List.unmodifiable(students);
  int get uid => -no;
}

class DraftSnapshot {
  final List<DraftGroup> groups;
  final List<int> slots;
  DraftSnapshot(List<DraftGroup> groups, List<int> slots)
    : groups = List.unmodifiable(groups.map((g) => g.copy())),
      slots = List.unmodifiable(slots);
}
