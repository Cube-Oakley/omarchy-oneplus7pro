// SPDX-License-Identifier: GPL-2.0-only
/* Development keyboard for the native Pixel. Text written to a root-only RAM
 * FIFO becomes Linux input events; keeps the uinput device alive between writes.
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static void fail(const char *s) { perror(s); exit(1); }
static void event(int fd, unsigned short type, unsigned short code, int value)
{
    struct input_event e = {.type=type,.code=code,.value=value};
    if(write(fd,&e,sizeof(e))!=sizeof(e)) fail("input event");
}
static void key(int fd, unsigned short code, int value)
{ event(fd,EV_KEY,code,value); event(fd,EV_SYN,SYN_REPORT,0); }
static void type(int fd, unsigned char c)
{
    static const int letters[]={KEY_A,KEY_B,KEY_C,KEY_D,KEY_E,KEY_F,KEY_G,KEY_H,KEY_I,KEY_J,KEY_K,KEY_L,KEY_M,KEY_N,KEY_O,KEY_P,KEY_Q,KEY_R,KEY_S,KEY_T,KEY_U,KEY_V,KEY_W,KEY_X,KEY_Y,KEY_Z};
    int code=0,shift=0;
    if(c>='A'&&c<='Z') { shift=1; c+='a'-'A'; }
    if(c>='a'&&c<='z') code=letters[c-'a'];
    else if(c>='1'&&c<='9') code=KEY_1+c-'1';
    else switch(c) {
        case '0':code=KEY_0;break; case ' ':code=KEY_SPACE;break;
        case '\n':case '\r':code=KEY_ENTER;break; case '\t':code=KEY_TAB;break;
        case '/':code=KEY_SLASH;break; case '.':code=KEY_DOT;break;
        case '>':code=KEY_DOT;shift=1;break; case '<':code=KEY_COMMA;shift=1;break;
        case '-':code=KEY_MINUS;break; case '_':code=KEY_MINUS;shift=1;break;
        case '=':code=KEY_EQUAL;break; case '+':code=KEY_EQUAL;shift=1;break;
        case '\'':code=KEY_APOSTROPHE;break; case '"':code=KEY_APOSTROPHE;shift=1;break;
        case ';':code=KEY_SEMICOLON;break; case ':':code=KEY_SEMICOLON;shift=1;break;
        case '$':code=KEY_4;shift=1;break; case '\\':code=KEY_BACKSLASH;break;
        case '|':code=KEY_BACKSLASH;shift=1;break;
        default:fprintf(stderr,"unsupported character %u\n",c);return;
    }
    if(shift) key(fd,KEY_LEFTSHIFT,1);
    key(fd,code,1); key(fd,code,0);
    if(shift) key(fd,KEY_LEFTSHIFT,0);
    usleep(15000);
}
int main(void)
{
    setvbuf(stdout,NULL,_IOLBF,0);
    int fd=open("/dev/uinput",O_WRONLY|O_NONBLOCK);
    if(fd<0) fail("uinput");
    if(ioctl(fd,UI_SET_EVBIT,EV_KEY)) fail("EV_KEY");
    for(int i=1;i<=KEY_CAPSLOCK;i++) if(ioctl(fd,UI_SET_KEYBIT,i)) fail("KEYBIT");
    struct uinput_setup setup={.id={.bustype=BUS_VIRTUAL,.vendor=0,.product=0,.version=1}};
    strcpy(setup.name,"Pixel USB development keyboard");
    if(ioctl(fd,UI_DEV_SETUP,&setup)||ioctl(fd,UI_DEV_CREATE)) fail("CREATE");
    const char *path="/run/pixel-input";
    if(mkfifo(path,0600)&&errno!=EEXIST) fail("mkfifo");
    struct stat st;
    if(lstat(path,&st)||!S_ISFIFO(st.st_mode)||st.st_uid!=0) { fputs("unsafe FIFO\n",stderr); return 1; }
    int in=open(path,O_RDWR|O_NOFOLLOW);
    if(in<0) fail("open FIFO");
    puts("PIXEL_VIRTUAL_KEYBOARD_READY");
    for(;;) {
        unsigned char c;
        ssize_t n=read(in,&c,1);
        if(n==1) type(fd,c);
        else if(n<0&&errno!=EINTR) fail("read");
    }
}
