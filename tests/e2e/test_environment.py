"""The test driver can run SDK tools while the server starts without SDK variables."""

from conftest import server_environment


def test_server_environment_does_not_remove_the_drivers_sdk_runtime():
    # arrange
    driver = {
        "PATH": "/pin/tools/bin:/usr/bin",
        "LD_LIBRARY_PATH": "/pin/runtime",
        "CANGJIE_HOME": "/pin",
        "CANGJIE_STDX_PATH": "/pin/stdx",
        "CANGJIE_SRC": "/pin/src",
        "DYLD_LIBRARY_PATH": "/pin/runtime",
        "DYLD_FALLBACK_LIBRARY_PATH": "/pin/fallback",
        "DYLD_FRAMEWORK_PATH": "/pin/framework",
        "CJLS_E2E_SDK": "/release",
    }

    # act
    server = server_environment(driver)

    # assert
    assert driver["LD_LIBRARY_PATH"] == "/pin/runtime"
    assert driver["CANGJIE_HOME"] == "/pin"
    assert server == {"PATH": driver["PATH"], "CJLS_E2E_SDK": "/release"}
