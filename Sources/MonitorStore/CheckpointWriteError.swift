/// The stored checkpoint changed after it was read, so the write was rejected.
public enum CheckpointWriteError: Error {
    case staleCheckpoint
}
