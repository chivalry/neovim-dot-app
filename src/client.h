#pragma once

#include <string>
#include <list>
#include <map>
#include <sstream>
#include <deque>

#include <msgpack.hpp>

#include "rpc.h"
#include "util.h"

class Process;

struct Event
{
    enum Type
    {
        Request,
        Response,
        Note
    } type;

    RPC *rpc;             // Response
    std::string name;     // Request | Note
    msgpack::object args; // Request | Note
    int msgid;            // Request
};

class Client: NoCopy
{
    friend class RPC;
    friend class Listener;

    public:
        typedef RPC::response_t response_t;

        Client(Process &);
        ~Client();

        template<typename Args>
        RPC *call(const std::string &name, Args args);
        Event wait();

        template<typename Result>
        void respond(const Event &, Result);

        template<typename Error>
        void signal_error(const Event &, Error);

    private:
        typedef std::map<int, RPC *> rpc_map_t;

        Process &process;
        msgpack::unpacker unpacker;
        msgpack::unpacked unpacked;
        rpc_map_t rpc_map;
        int next_id;
        pthread_mutex_t mutex;

        void respond(int msgid, msgpack::object err, msgpack::object result);
        void send(const std::string &message);
};

template<typename Args>
RPC *Client::call(const std::string &name, Args args)
{
    typedef msgpack::type::tuple<int, int, std::string, Args> call_t;

    int msgid = next_id++;

    call_t request(
        0, // 0=request, 1=response
        msgid,
        name,
        args
    );

    std::stringstream buffer;
    msgpack::pack(buffer, request);
    std::string msg = buffer.str();
    send(msg);

    RPC *rpc = new RPC(*this, msgid);
    return rpc;
}

template<typename Result>
void Client::respond(const Event &event, Result arg)
{
    msgpack::object arg_o;
    msgpack::object err_o;

    arg_o << arg;
    respond(event.msgid, err_o, arg_o);
}

template<typename Error>
void Client::signal_error(const Event &event, Error error)
{
    msgpack::object arg_o;
    msgpack::object err_o;

    err_o << error;
    respond(event.msgid, err_o, arg_o);
}
