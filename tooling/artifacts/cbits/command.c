#include <sys/types.h>
#include <sys/wait.h>

/* Observe completion without reaping the process-group identity anchor. */
int bepis_artifact_child_exited(int pid)
{
    siginfo_t status = {0};
    if (waitid(P_PID, (id_t)pid, &status, WEXITED | WNOHANG | WNOWAIT) == -1)
        return -1;
    return status.si_pid != 0;
}
