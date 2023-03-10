defmodule Chessh.SSH.Tui do
  alias Chessh.{Repo, PlayerSession, Utils, Player}
  alias Chessh.SSH.Client

  alias IO.ANSI

  require Logger

  @behaviour :ssh_server_channel
  @session_closed_message [
    ANSI.clear(),
    ["This session has been closed"]
  ]

  defmodule State do
    defstruct channel_id: nil,
              width: nil,
              height: nil,
              client_pid: nil,
              connection_ref: nil,
              player_session: nil
  end

  def init([%State{} = init_state]) do
    :syn.add_node_to_scopes([:player_sessions])
    {:ok, init_state}
  end

  def handle_msg({:ssh_channel_up, channel_id, connection_ref}, %State{} = state) do
    Logger.debug("SSH channel up #{inspect(:ssh.connection_info(connection_ref))}")

    connected_player =
      :ssh.connection_info(connection_ref)
      |> Keyword.fetch!(:user)
      |> String.Chars.to_string()

    case Repo.get_by(Player, username: connected_player) do
      nil ->
        Logger.error("Killing channel #{channel_id} - auth'd user does not exist")
        {:stop, channel_id, state}

      player ->
        case Repo.get_by(PlayerSession,
               node_id: System.fetch_env!("NODE_ID"),
               process: Utils.pid_to_str(connection_ref),
               player_id: player.id
             ) do
          nil ->
            Logger.error("Killing channel #{channel_id} - session does not exist")
            {:stop, channel_id, state}

          session ->
            Logger.debug("Subscribing to session #{session.id}")
            :syn.join(:player_sessions, {:session, session.id}, self())

            {:ok,
             %State{
               state
               | channel_id: channel_id,
                 connection_ref: connection_ref,
                 player_session: session
             }}
        end
    end
  end

  def handle_msg(
        {:EXIT, client_pid, _reason},
        %State{client_pid: client_pid, channel_id: channel_id} = state
      ) do
    send(client_pid, :quit)
    {:stop, channel_id, state}
  end

  def handle_msg(
        {:send_data, data},
        %State{connection_ref: connection_ref, channel_id: channel_id} = state
      ) do
    :ssh_connection.send(connection_ref, channel_id, data)
    {:ok, state}
  end

  def handle_msg(
        :session_closed,
        %State{connection_ref: connection_ref, channel_id: channel_id} = state
      ) do
    :ssh_connection.send(connection_ref, channel_id, @session_closed_message)
    {:stop, channel_id, state}
  end

  def handle_msg(msg, term) do
    Logger.debug("Unknown msg #{inspect(msg)}, #{inspect(term)}")
  end

  def handle_ssh_msg(
        {:ssh_cm, _connection_handler, {:data, _channel_id, _type, data}},
        %State{} = state
      ) do
    send(state.client_pid, {:data, data})
    {:ok, state}
  end

  def handle_ssh_msg(
        {:ssh_cm, connection_handler,
         {:pty, channel_id, want_reply?, {_term, width, height, _pixwidth, _pixheight, _opts}}},
        %State{} = state
      ) do
    Logger.debug("#{inspect(state.player_session)} has requested a PTY")
    :ssh_connection.reply_request(connection_handler, want_reply?, :success, channel_id)

    {:ok,
     %{
       state
       | width: width,
         height: height
     }}
  end

  def handle_ssh_msg(
        {:ssh_cm, connection_handler, {:env, channel_id, want_reply?, var, value}},
        state
      ) do
    :ssh_connection.reply_request(connection_handler, want_reply?, :failure, channel_id)
    Logger.debug("ENV #{var} = #{value}")
    {:ok, state}
  end

  def handle_ssh_msg(
        {:ssh_cm, _connection_handler,
         {:window_change, _channel_id, width, height, _pixwidth, _pixheight}},
        %State{client_pid: client_pid} = state
      ) do
    send(client_pid, {:resize, {width, height}})

    {:ok,
     %State{
       state
       | width: width,
         height: height
     }}
  end

  def handle_ssh_msg(
        {:ssh_cm, connection_handler, {:shell, channel_id, want_reply?}},
        %{width: width, height: height, player_session: player_session} = state
      ) do
    :ssh_connection.reply_request(connection_handler, want_reply?, :success, channel_id)

    {:ok, client_pid} =
      GenServer.start_link(Client, [
        %Client.State{
          tui_pid: self(),
          width: width,
          player_session: player_session,
          height: height
        }
      ])

    send(client_pid, :refresh)
    {:ok, %State{state | client_pid: client_pid}}
  end

  def handle_ssh_msg(
        msg,
        %State{channel_id: channel_id} = state
      ) do
    Logger.debug("UNKOWN MESSAGE #{inspect(msg)}")
    {:stop, channel_id, state}
  end

  def terminate(_reason, _state) do
    :ok
  end
end
