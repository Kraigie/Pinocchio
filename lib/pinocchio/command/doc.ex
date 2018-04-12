defmodule Pinocchio.Command.Doc do
  alias Kernel.Typespec

  defp elixir_module?(module) do
    function_exported?(module, :__info__, 1)
  end

  defp print_doc(heading, types, doc) do
    {heading, types, doc}
  end

  defp print_typespec({types, doc}) do
    "types #{inspect(types)} doc: #{inspect(doc)}"
  end

  def docs_not_found(for), do: "no docs in this module: #{inspect(for)}"
  def no_docs(for), do: "compiled without docs: #{inspect(for)}"
  def puts_error(for), do: "docs not found: #{inspect(for)}"
  def behaviour_found(for), do: "behaviour_found: #{inspect(for)}"
  def type_found(for), do: "type found: #{inspect(for)}"

  defp has_callback?(mod, fun) do
    mod
    |> Code.get_docs(:callback_docs)
    |> Enum.any?(&match?({{^fun, _}, _, _, _}, &1))
  end

  defp has_callback?(mod, fun, arity) do
    mod
    |> Code.get_docs(:callback_docs)
    |> Enum.any?(&match?({{^fun, ^arity}, _, _, _}, &1))
  end

  defp has_type?(mod, fun) do
    mod
    |> Code.get_docs(:type_docs)
    |> Enum.any?(&match?({{^fun, _}, _, _, _}, &1))
  end

  defp has_type?(mod, fun, arity) do
    mod
    |> Code.get_docs(:type_docs)
    |> Enum.any?(&match?({{^fun, ^arity}, _, _, _}, &1))
  end

  defp print_fun(mod, {{fun, arity}, _line, kind, args, doc}, spec) do
    if callback_module = is_nil(doc) and callback_module(mod, fun, arity) do
      filter = &match?({^fun, ^arity}, elem(&1, 0))

      case get_callback_docs(callback_module, filter) do
        {:ok, callback_docs} -> Enum.each(callback_docs, &print_typespec/1)
        _ -> nil
      end
    else
      args = Enum.map_join(args, ", ", &format_doc_arg(&1))
      print_doc("#{kind} #{fun}(#{args})", spec, doc)
    end
  end

  defp format_doc_arg({:\\, _, [left, right]}) do
    format_doc_arg(left) <> " \\\\ " <> Macro.to_string(right)
  end

  defp format_doc_arg({var, _, _}) do
    Atom.to_string(var)
  end

  defp format_typespec(definition, kind, _nesting) do
    IO.inspect("@#{kind} #{Macro.to_string(definition)}")
  end

  defp format_callback(kind, name, key, callbacks) do
    {_, specs} = List.keyfind(callbacks, key, 0)

    Enum.map(specs, fn spec ->
      Typespec.spec_to_ast(name, spec)
      |> Macro.prewalk(&drop_macro_env/1)
      |> format_typespec(kind, 0)
    end)
  end

  defp drop_macro_env({name, meta, [{:::, _, [_, {{:., _, [Macro.Env, :t]}, _, _}]} | args]}),
    do: {name, meta, args}

  defp drop_macro_env(other), do: other

  defp get_callback_docs(mod, filter) do
    callbacks = Typespec.beam_callbacks(mod)
    docs = Code.get_docs(mod, :callback_docs)

    cond do
      is_nil(callbacks) ->
        :no_beam

      is_nil(docs) ->
        :no_docs

      true ->
        docs =
          docs
          |> Enum.filter(filter)
          |> Enum.map(fn
            {{fun, arity}, _, :macrocallback, doc} ->
              macro = {:"MACRO-#{fun}", arity + 1}
              {format_callback(:macrocallback, fun, macro, callbacks), doc}

            {{fun, arity}, _, kind, doc} ->
              {format_callback(kind, fun, {fun, arity}, callbacks), doc}
          end)

        {:ok, docs}
    end
  end

  defp callback_module(mod, fun, arity) do
    predicate = &match?({{^fun, ^arity}, _}, &1)

    mod.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> Stream.concat()
    |> Enum.find(&Enum.any?(Typespec.beam_callbacks(&1), predicate))
  end

  defp get_spec(module, name, arity) do
    all_specs = Typespec.beam_specs(module) || []

    case List.keyfind(all_specs, {name, arity}, 0) do
      {_, specs} ->
        formatted =
          Enum.map(specs, fn spec ->
            Typespec.spec_to_ast(name, spec)
            |> format_typespec(:spec, 2)
          end)

        [formatted, ?\n]

      nil ->
        []
    end
  end

  defp h_mod_fun_arity(mod, fun, arity) when is_atom(mod) do
    docs = Code.get_docs(mod, :docs)
    spec = get_spec(mod, fun, arity)

    cond do
      doc_tuple = find_doc(docs, fun, arity) ->
        print_fun(mod, doc_tuple, spec)

      docs && has_callback?(mod, fun, arity) ->
        :behaviour_found

      docs && has_type?(mod, fun, arity) ->
        :type_found

      is_nil(docs) and spec != [] ->
        message =
          if elixir_module?(mod) do
            IO.inspect("Module was compiled without docs. Showing only specs.")
          else
            IO.inspect(
              "Documentation is not available for non-Elixir modules. Showing only specs."
            )
          end

        {:ok, print_doc("#{inspect(mod)}.#{fun}/#{arity}", spec, message)}

      is_nil(docs) and elixir_module?(mod) ->
        :no_docs

      true ->
        :not_found
    end
  end

  defp find_doc(nil, _fun, _arity) do
    nil
  end

  defp find_doc(docs, fun, arity) do
    doc = List.keyfind(docs, {fun, arity}, 0) || find_doc_defaults(docs, fun, arity)
    if doc != nil and has_content?(doc), do: doc
  end

  defp find_doc_defaults(docs, function, min) do
    Enum.find(docs, fn doc ->
      case elem(doc, 0) do
        {^function, arity} when arity > min ->
          defaults = Enum.count(elem(doc, 3), &match?({:\\, _, _}, &1))
          arity <= min + defaults

        _ ->
          false
      end
    end)
  end

  defp has_content?({_, _, _, _, false}), do: false
  defp has_content?({{name, _}, _, _, _, nil}), do: hd(Atom.to_charlist(name)) != ?_
  defp has_content?({_, _, _, _, _}), do: true

  def h(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _} ->
        if elixir_module?(module) do
          case Code.get_docs(module, :moduledoc) do
            {_, binary} when is_binary(binary) ->
              print_doc(inspect(module), [], binary)

            {_, _} ->
              docs_not_found(inspect(module))

            _ ->
              no_docs(module)
          end
        else
          puts_error(
            "Documentation is not available for non-Elixir modules, got: #{inspect(module)}"
          )
        end

      {:error, reason} ->
        puts_error("Could not load module #{inspect(module)}, got: #{reason}")
    end
  end

  def h({module, function}) when is_atom(module) and is_atom(function) do
    case Code.ensure_loaded(module) do
      {:module, _} ->
        docs = Code.get_docs(module, :docs)

        exports =
          cond do
            docs ->
              Enum.map(docs, &elem(&1, 0))

            function_exported?(module, :__info__, 1) ->
              module.__info__(:functions) ++ module.__info__(:macros)

            true ->
              module.module_info(:exports)
          end

        result =
          for {^function, arity} <- exports,
              (if docs do
                 find_doc(docs, function, arity)
               else
                 get_spec(module, function, arity) != []
               end) do
            h_mod_fun_arity(module, function, arity)
          end

        cond do
          result != [] ->
            [fun] = result
            fun

          docs && has_callback?(module, function) ->
            behaviour_found("#{inspect(module)}.#{function}")

          docs && has_type?(module, function) ->
            type_found("#{inspect(module)}.#{function}")

          elixir_module?(module) and is_nil(docs) ->
            no_docs(module)

          true ->
            docs_not_found("#{inspect(module)}.#{function}")
        end

      {:error, reason} ->
        puts_error("Could not load module #{inspect(module)}, got: #{reason}")
    end
  end

  def h({module, function, arity})
      when is_atom(module) and is_atom(function) and is_integer(arity) do
    case Code.ensure_loaded(module) do
      {:module, _} ->
        case h_mod_fun_arity(module, function, arity) do
          {:ok, docs} ->
            docs

          :behaviour_found ->
            behaviour_found("#{inspect(module)}.#{function}/#{arity}")

          :type_found ->
            type_found("#{inspect(module)}.#{function}/#{arity}")

          :no_docs ->
            no_docs(module)

          :not_found ->
            docs_not_found("#{inspect(module)}.#{function}/#{arity}")
        end

      {:error, reason} ->
        puts_error("Could not load module #{inspect(module)}, got: #{reason}")
    end
  end

  def h(invalid) do
    puts_error("Invalid arguments for h helper: #{inspect(invalid)}")
  end
end
