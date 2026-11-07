use std::ptr;

// Reuse the generated C API; this test observer needs only terminal parsing and formatting.
use ghostty_vt::ffi;

struct Screen {
    terminal: ffi::GhosttyTerminal,
    formatter: ffi::GhosttyFormatter,
}

impl Drop for Screen {
    fn drop(&mut self) {
        unsafe {
            ffi::ghostty_formatter_free(self.formatter);
            ffi::ghostty_terminal_free(self.terminal);
        }
    }
}

pub fn text(output: &[u8], cols: u16, rows: u16) -> String {
    let mut screen = Screen {
        terminal: ptr::null_mut(),
        formatter: ptr::null_mut(),
    };
    // Plain text, trimmed, not unwrapped, with no extras.
    let emit = ffi::GhosttyFormatterFormat_GHOSTTY_FORMATTER_FORMAT_PLAIN;
    let trim = true;
    let unwrap = false;
    let extras: ffi::GhosttyFormatterExtras = 0;
    unsafe {
        assert_eq!(
            ffi::ghostty_terminal_new(ptr::null(), &mut screen.terminal, cols, rows),
            ffi::GhosttyResult_GHOSTTY_SUCCESS
        );
        ffi::ghostty_terminal_vt_write(screen.terminal, output.as_ptr(), output.len());
        assert_eq!(
            ffi::ghostty_formatter_terminal_new(
                ptr::null(),
                &mut screen.formatter,
                screen.terminal
            ),
            ffi::GhosttyResult_GHOSTTY_SUCCESS
        );
        for (option, value) in [
            (
                ffi::GhosttyFormatterOption_GHOSTTY_FORMATTER_OPT_EMIT,
                (&emit as *const ffi::GhosttyFormatterFormat).cast(),
            ),
            (
                ffi::GhosttyFormatterOption_GHOSTTY_FORMATTER_OPT_TRIM,
                (&trim as *const bool).cast(),
            ),
            (
                ffi::GhosttyFormatterOption_GHOSTTY_FORMATTER_OPT_UNWRAP,
                (&unwrap as *const bool).cast(),
            ),
            (
                ffi::GhosttyFormatterOption_GHOSTTY_FORMATTER_OPT_EXTRAS,
                (&extras as *const ffi::GhosttyFormatterExtras).cast(),
            ),
        ] {
            assert_eq!(
                ffi::ghostty_formatter_set(screen.formatter, option, value),
                ffi::GhosttyResult_GHOSTTY_SUCCESS
            );
        }
        let mut len = 0;
        let result =
            ffi::ghostty_formatter_format_buf(screen.formatter, ptr::null_mut(), 0, &mut len);
        assert!(matches!(
            result,
            ffi::GhosttyResult_GHOSTTY_SUCCESS | ffi::GhosttyResult_GHOSTTY_OUT_OF_SPACE
        ));
        let mut bytes = vec![0; len];
        assert_eq!(
            ffi::ghostty_formatter_format_buf(
                screen.formatter,
                bytes.as_mut_ptr(),
                bytes.len(),
                &mut len
            ),
            ffi::GhosttyResult_GHOSTTY_SUCCESS
        );
        String::from_utf8_lossy(&bytes[..len]).into_owned()
    }
}

#[test]
fn screen_text_reconstructs_partial_redraws() {
    let output = b"REMOTE_SURVIVED\x1b[1;8HSTILL_SELECTED";
    assert!(!output
        .windows(b"REMOTE_STILL_SELECTED".len())
        .any(|part| part == b"REMOTE_STILL_SELECTED"));
    assert!(text(output, 80, 24).contains("REMOTE_STILL_SELECTED"));
}
