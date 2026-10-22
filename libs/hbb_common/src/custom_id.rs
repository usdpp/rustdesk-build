pub fn is_valid_custom_id(id: &str) -> bool {
    let bytes = id.as_bytes();
    if !(6..=16).contains(&bytes.len()) || !bytes[0].is_ascii_alphanumeric() {
        return false;
    }
    bytes
        .iter()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(*byte, b'_' | b'-'))
}

#[cfg(test)]
mod tests {
    use super::is_valid_custom_id;

    #[test]
    fn accepts_numeric_and_named_ids() {
        assert!(is_valid_custom_id("123456789"));
        assert!(is_valid_custom_id("Office-PC_01"));
        assert!(is_valid_custom_id("Windows-J4125"));
    }

    #[test]
    fn rejects_unsafe_or_out_of_range_ids() {
        assert!(!is_valid_custom_id("short"));
        assert!(!is_valid_custom_id("-office01"));
        assert!(!is_valid_custom_id("office.pc"));
        assert!(!is_valid_custom_id("office pc"));
        assert!(!is_valid_custom_id("12345678901234567"));
        assert!(!is_valid_custom_id("设备-123456"));
    }
}
