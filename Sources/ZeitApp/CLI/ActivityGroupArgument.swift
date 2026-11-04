import ArgumentParser

/// Lets `--group work|personal_projects|personal` be parsed straight into the enum,
/// so an unknown group is rejected by ArgumentParser with the valid values listed.
extension ActivityGroup: ExpressibleByArgument {}
