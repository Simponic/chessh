defmodule Chessh.SSH.Client.Screen do
  @callback handle_info(
              {:render, width :: integer(), height :: integer()},
              state :: any()
            ) ::
              {:noreply, any()}
  @callback handle_info({:input, width :: integer(), height :: integer(), action :: any()}) ::
              {:noreply, any()}

  #  @callback render(state :: Chessh.SSH.Client.State.t() | any()) :: any()
  #  @callback handle_input(action :: any(), state :: Chessh.SSH.Client.State.t()) ::
  #              Chessh.SSH.Client.State.t()

  defmacro __using__(_) do
    quote do
      @behaviour Chessh.SSH.Client.Screen
      use GenServer

      @ascii_chars Application.compile_env!(:chessh, :ascii_chars_json_file)
                   |> File.read!()
                   |> Jason.decode!()

      def center_rect({rect_width, rect_height}, {parent_width, parent_height}) do
        {
          div(parent_height - rect_height, 2),
          div(parent_width - rect_width, 2)
        }
      end
    end
  end
end
