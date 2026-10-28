#[cfg(feature = "nvidia")]
pub mod nvidia;

#[cfg(target_os = "windows")]
pub mod windows;

cfg_select! {
    all(target_os = "linux", feature = "gpu") =>{
        pub mod intel;
        pub mod amd;
    }
    _ => {}
}
