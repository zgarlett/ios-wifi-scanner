#import <sys/types.h>
#import <sys/socket.h>
#import <sys/sysctl.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <ifaddrs.h>

// Manual definitions from <net/route.h> — that header is excluded from the iOS SDK.
#ifndef NET_RT_FLAGS
#define NET_RT_FLAGS    4
#endif
#ifndef RTF_LLINFO
#define RTF_LLINFO      0x400
#endif
#define RTAX_DST        0
#define RTAX_GATEWAY    1
#define RTAX_MAX        8

struct rt_metrics_ws {
    uint32_t rmx_locks;
    uint32_t rmx_mtu;
    uint32_t rmx_hopcount;
    int32_t  rmx_expire;
    uint32_t rmx_recvpipe;
    uint32_t rmx_sendpipe;
    uint32_t rmx_ssthresh;
    uint32_t rmx_rtt;
    uint32_t rmx_rttvar;
    uint32_t rmx_pksent;
    uint32_t rmx_state;
    uint32_t rmx_filler[3];
};

struct rt_msghdr_ws {
    uint16_t            rtm_msglen;
    uint8_t             rtm_version;
    uint8_t             rtm_type;
    uint16_t            rtm_index;
    uint16_t            _rtm_spare1;
    int32_t             rtm_flags;
    int32_t             rtm_addrs;
    int32_t             rtm_pid;
    int32_t             rtm_seq;
    int32_t             rtm_errno;
    int32_t             rtm_use;
    uint32_t            rtm_inits;
    struct rt_metrics_ws rtm_rmx;
};
