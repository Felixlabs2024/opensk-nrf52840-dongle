#![no_std]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    // 原 crate 使用 core::intrinsics::abort(),该内部 API 在较新 nightly 中已被移除。
    // 改为按架构直接触发 CPU 陷阱指令,语义等价(panic -> 停机)。
    #[cfg(target_arch = "arm")]
    unsafe { core::arch::asm!("udf #0xfe", options(noreturn)) };
    #[cfg(target_arch = "x86_64")]
    unsafe { core::arch::asm!("int3", options(noreturn)) };
    #[cfg(not(any(target_arch = "arm", target_arch = "x86_64")))]
    loop {
        core::hint::spin_loop();
    }
}
