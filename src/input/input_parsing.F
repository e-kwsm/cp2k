!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief routines that parse the input
!> \par History
!>      06.2004 created
!> \author fawzi
! **************************************************************************************************
MODULE input_parsing
   USE cp_linked_list_input,            ONLY: &
        cp_create, cp_dealloc, cp_sll_char_type, cp_sll_int_type, cp_sll_logical_type, &
        cp_sll_real_type, cp_sll_val_create, cp_sll_val_type, cp_to_array
   USE cp_log_handling,                 ONLY: cp_logger_get_default_io_unit,&
                                              cp_to_string
   USE cp_parser_methods,               ONLY: parser_get_object,&
                                              parser_location,&
                                              parser_skip_space,&
                                              parser_test_next_token
   USE cp_parser_types,                 ONLY: cp_parser_type
   USE cp_units,                        ONLY: cp_unit_compatible,&
                                              cp_unit_create,&
                                              cp_unit_desc,&
                                              cp_unit_release,&
                                              cp_unit_set_type,&
                                              cp_unit_to_cp2k1,&
                                              cp_unit_type
   USE input_enumeration_types,         ONLY: enum_c2i,&
                                              enumeration_type
   USE input_keyword_types,             ONLY: keyword_describe,&
                                              keyword_type
   USE input_section_types,             ONLY: &
        section_describe, section_get_keyword, section_get_keyword_index, &
        section_get_subsection_index, section_type, section_typo_match, section_vals_add_values, &
        section_vals_type, typo_match_section, typo_matching_line, typo_matching_rank
   USE input_val_types,                 ONLY: &
        char_t, enum_t, integer_t, lchar_t, logical_t, no_t, real_t, val_create, val_type
   USE kinds,                           ONLY: default_string_length,&
                                              dp,&
                                              max_line_length
   USE string_utilities,                ONLY: uppercase
#include "../base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE

   LOGICAL, PRIVATE, PARAMETER :: debug_this_module = .TRUE.
   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'input_parsing'

   PUBLIC :: section_vals_parse
!***
CONTAINS

! **************************************************************************************************
!> \brief ...
!> \param section_vals ...
!> \param parser ...
!> \param default_units ...
!> \param root_section if the root section should be parsed (defaults to true)
!> \author fawzi
! **************************************************************************************************
   RECURSIVE SUBROUTINE section_vals_parse(section_vals, parser, default_units, root_section)
      TYPE(section_vals_type), POINTER                   :: section_vals
      TYPE(cp_parser_type), INTENT(INOUT)                :: parser
      TYPE(cp_unit_set_type), INTENT(IN)                 :: default_units
      LOGICAL, INTENT(in), OPTIONAL                      :: root_section

      CHARACTER(len=*), PARAMETER :: routineN = 'section_vals_parse'

      CHARACTER(len=max_line_length)                     :: token
      INTEGER                                            :: desc_level, handle, ik, imatch, irs, is, &
                                                            nsub, output_unit
      LOGICAL                                            :: at_end, compatible_end, root_sect, &
                                                            whole_section
      TYPE(cp_sll_val_type), POINTER                     :: last_val, new_val, previous_last, &
                                                            previous_list
      TYPE(keyword_type), POINTER                        :: keyword
      TYPE(section_type), POINTER                        :: section
      TYPE(val_type), POINTER                            :: el

      CALL timeset(routineN, handle)

      NULLIFY (previous_list, previous_last)

      root_sect = .TRUE.
      IF (PRESENT(root_section)) root_sect = root_section

      CPASSERT(ASSOCIATED(section_vals))
      output_unit = cp_logger_get_default_io_unit()

      CPASSERT(section_vals%ref_count > 0)
      IF (root_sect .AND. parser%icol1 > parser%icol2) &
         CALL cp_abort(__LOCATION__, &
                       "Error 1: this routine must be called just after having parsed the start of the section " &
                       //TRIM(parser_location(parser)))
      section => section_vals%section
      IF (root_sect) THEN
         token = TRIM(ADJUSTL(parser%input_line(parser%icol1:parser%icol2))) ! Ignore leading or trailing blanks
         CALL uppercase(token)
         IF (token /= parser%section_character//section%name) &
            CALL cp_abort(__LOCATION__, &
                          "Error 2: this routine must be called just after having parsed the start of the section " &
                          //TRIM(parser_location(parser)))
      END IF
      IF (.NOT. section%repeats .AND. SIZE(section_vals%values, 2) /= 0) &
         CALL cp_abort(__LOCATION__, "Section "//TRIM(section%name)// &
                       " should not repeat "//TRIM(parser_location(parser)))
      CALL section_vals_add_values(section_vals)
      irs = SIZE(section_vals%values, 2)

      IF (ALLOCATED(section%deprecation_notice)) THEN
         CALL cp_warn(__LOCATION__, &
                      "The specified section '"//TRIM(section%name)// &
                      "' is deprecated and may be removed in a future version: "// &
                      section%deprecation_notice)
      END IF

      IF (ASSOCIATED(section%keywords(-1)%keyword)) THEN ! reads section params
         keyword => section%keywords(-1)%keyword
         NULLIFY (el)
         IF (keyword%type_of_var == lchar_t) CALL parser_skip_space(parser)
         CALL val_create_parsing(el, type_of_var=keyword%type_of_var, &
                                 n_var=keyword%n_var, default_value=keyword%lone_keyword_value, &
                                 enum=keyword%enum, unit=keyword%unit, &
                                 default_units=default_units, &
                                 parser=parser)
         NULLIFY (new_val)
         CALL cp_sll_val_create(new_val, el)
         section_vals%values(-1, irs)%list => new_val
         NULLIFY (el)
      END IF
      DO WHILE (.TRUE.)
         CALL parser_get_object(parser, token, newline=.TRUE., &
                                lower_to_upper=.TRUE., at_end=at_end)
         token = TRIM(ADJUSTL(token)) ! Ignore leading or trailing blanks
         IF (at_end) THEN
            IF (root_sect) &
               CALL cp_abort(__LOCATION__, &
                             "unexpected end of file while parsing section "// &
                             TRIM(section%name)//" "//TRIM(parser_location(parser)))
            EXIT
         END IF
         IF (token(1:1) == parser%section_character) THEN
            IF (token == "&END") THEN
               ! end of section
               compatible_end = .TRUE.
               IF (parser_test_next_token(parser) /= "EOL") THEN
                  CALL parser_get_object(parser, token, newline=.FALSE., &
                                         lower_to_upper=.TRUE.)
                  IF (token /= "SECTION" .AND. token /= section%name) THEN
                     compatible_end = .FALSE.
                  END IF
               END IF
               IF (parser_test_next_token(parser) /= "EOL") THEN
                  CALL parser_get_object(parser, token, newline=.FALSE., &
                                         lower_to_upper=.TRUE.)
                  IF (token /= section%name) THEN
                     PRINT *, TRIM(token), "/=", TRIM(section%name)
                     compatible_end = .FALSE.
                  END IF
               END IF
               IF (.NOT. compatible_end) THEN
                  CALL cp_abort(__LOCATION__, &
                                "non-compatible end of section "//TRIM(section%name)//" "// &
                                TRIM(parser_location(parser)))
               END IF
               !              RETURN
               EXIT
            END IF
            is = section_get_subsection_index(section, token(2:))
            IF (is > 0) THEN
               CALL section_vals_parse(section_vals%subs_vals(is, irs)%section_vals, &
                                       default_units=default_units, parser=parser)
            ELSE
               ! unknown subsection
               IF (output_unit > 0) THEN
                  WRITE (output_unit, *)
                  WRITE (output_unit, '(T2,A)') "Possible matches for unknown subsection "
                  WRITE (output_unit, *)
                  WRITE (output_unit, '(T2,A)') TRIM(token(2:))
                  WRITE (output_unit, *)
                  CALL section_typo_match(typo_match_section, TRIM(section%name), TRIM(token(2:)), "", &
                                          typo_matching_rank, typo_matching_line, bonus=0)
                  DO imatch = 1, SIZE(typo_matching_rank)
                     WRITE (output_unit, '(T2,A,1X,I0)') TRIM(typo_matching_line(imatch))//" score: ", typo_matching_rank(imatch)
                  END DO
               END IF
               CALL cp_abort(__LOCATION__, &
                             "unknown subsection "//TRIM(token(2:))//" of section " &
                             //TRIM(section%name))
               nSub = 1
               DO WHILE (nSub > 0)
                  CALL parser_get_object(parser, token, newline=.TRUE., &
                                         lower_to_upper=.TRUE.)
                  IF (token(1:1) == parser%section_character) THEN
                     IF (token == "&END") THEN
                        nSub = nSub - 1
                     ELSE
                        nSub = nSub + 1
                     END IF
                  END IF
               END DO
            END IF
         ELSE ! token is a keyword
            IF (token == "DESCRIBE") THEN
               IF (output_unit > 0) WRITE (output_unit, "(/,' ****** DESCRIPTION ******',/)")
               desc_level = 3
               IF (parser_test_next_token(parser) == "INT") THEN
                  CALL parser_get_object(parser, desc_level)
               END IF
               whole_section = .TRUE.
               DO WHILE (parser_test_next_token(parser) == "STR")
                  whole_section = .FALSE.
                  CALL parser_get_object(parser, token, newline=.FALSE., &
                                         lower_to_upper=.TRUE.)
                  keyword => section_get_keyword(section, token)
                  IF (.NOT. ASSOCIATED(keyword)) THEN
                     CALL cp_warn(__LOCATION__, &
                                  "unknown keyword to describe "//TRIM(token)// &
                                  " in section "//TRIM(section%name))
                  ELSE
                     CALL keyword_describe(keyword, output_unit, desc_level)
                  END IF
               END DO
               IF (whole_section) THEN
                  CALL section_describe(section, output_unit, desc_level, hide_root=.NOT. root_sect)
               END IF
               IF (output_unit > 0) WRITE (output_unit, "(/,' ****** =========== ******',/)")

            ELSE ! token is a "normal" keyword
               ik = section_get_keyword_index(section, token)
               IF (ik < 1) THEN ! don't accept pseudo keyword names
                  parser%icol = parser%icol1 - 1 ! re-read also the actual token
                  ik = 0
                  IF (.NOT. ASSOCIATED(section%keywords(0)%keyword)) THEN
                     IF (output_unit > 0) THEN
                        WRITE (output_unit, *)
                        WRITE (output_unit, '(T2,A)') "Possible matches for unknown keyword "
                        WRITE (output_unit, *)
                        WRITE (output_unit, '(T2,A)') TRIM(token)
                        WRITE (output_unit, *)
                        CALL section_typo_match(typo_match_section, TRIM(section%name), TRIM(token), "", &
                                                typo_matching_rank, typo_matching_line, bonus=0)
                        DO imatch = 1, SIZE(typo_matching_rank)
                           WRITE (output_unit, '(T2,A,1X,I0)') &
                              TRIM(typo_matching_line(imatch))//" score: ", typo_matching_rank(imatch)
                        END DO
                     END IF
                     CALL cp_abort(__LOCATION__, &
                                   "found an unknown keyword "//TRIM(token)// &
                                   " in section "//TRIM(section%name))
                  END IF
               END IF
               keyword => section%keywords(ik)%keyword
               IF (ASSOCIATED(keyword)) THEN
                  IF (keyword%removed) THEN
                     IF (ALLOCATED(keyword%deprecation_notice)) THEN
                        CALL cp_abort(__LOCATION__, &
                                      "The specified keyword '"//TRIM(token)//"' is not available anymore: "// &
                                      keyword%deprecation_notice)
                     ELSE
                        CALL cp_abort(__LOCATION__, &
                                      "The specified keyword '"//TRIM(token)// &
                                      "' is not available anymore, please consult the manual.")
                     END IF
                  END IF

                  IF (ALLOCATED(keyword%deprecation_notice)) &
                     CALL cp_warn(__LOCATION__, &
                                  "The specified keyword '"//TRIM(token)// &
                                  "' is deprecated and may be removed in a future version: "// &
                                  keyword%deprecation_notice//".")

                  NULLIFY (el)
                  IF (ik /= 0 .AND. keyword%type_of_var == lchar_t) &
                     CALL parser_skip_space(parser)
                  CALL val_create_parsing(el, type_of_var=keyword%type_of_var, &
                                          n_var=keyword%n_var, default_value=keyword%lone_keyword_value, &
                                          enum=keyword%enum, unit=keyword%unit, &
                                          default_units=default_units, parser=parser)
                  IF (ASSOCIATED(el)) THEN
                     NULLIFY (new_val)
                     CALL cp_sll_val_create(new_val, el)
                     last_val => section_vals%values(ik, irs)%list
                     IF (.NOT. ASSOCIATED(last_val)) THEN
                        section_vals%values(ik, irs)%list => new_val
                     ELSE
                        IF (.NOT. keyword%repeats) &
                           CALL cp_abort(__LOCATION__, &
                                         "Keyword "//TRIM(token)// &
                                         " in section "//TRIM(section%name)//" should not repeat.")
                        IF (ASSOCIATED(last_val, previous_list)) THEN
                           last_val => previous_last
                        ELSE
                           previous_list => last_val
                        END IF
                        DO WHILE (ASSOCIATED(last_val%rest))
                           last_val => last_val%rest
                        END DO
                        last_val%rest => new_val
                        previous_last => new_val
                     END IF
                  END IF
               END IF
            END IF
         END IF
      END DO
      CALL timestop(handle)
   END SUBROUTINE section_vals_parse

! **************************************************************************************************
!> \brief creates a val_type object by parsing the values
!> \param val the value that will be created
!> \param type_of_var type of the value to be created
!> \param n_var number of values to be parsed (-1: undefined)
!> \param enum ...
!> \param parser the parser from where the values should be read
!> \param unit ...
!> \param default_units ...
!> \param default_value a default value if nothing is found (can be null)
!> \author fawzi
!> \note
!>      - no_t does not create a value
! **************************************************************************************************
   SUBROUTINE val_create_parsing(val, type_of_var, n_var, enum, &
                                 parser, unit, default_units, default_value)
      TYPE(val_type), POINTER                            :: val
      INTEGER, INTENT(in)                                :: type_of_var, n_var
      TYPE(enumeration_type), POINTER                    :: enum
      TYPE(cp_parser_type), INTENT(INOUT)                :: parser
      TYPE(cp_unit_type), POINTER                        :: unit
      TYPE(cp_unit_set_type), INTENT(IN)                 :: default_units
      TYPE(val_type), OPTIONAL, POINTER                  :: default_value

      CHARACTER(len=*), PARAMETER :: routineN = 'val_create_parsing'

      CHARACTER(len=default_string_length)               :: c_val, info, location
      CHARACTER(len=default_string_length), &
         DIMENSION(:), POINTER                           :: c_val_p
      INTEGER                                            :: handle, i, i_val
      INTEGER, DIMENSION(:), POINTER                     :: i_val_p
      LOGICAL                                            :: check, eol, l_val, quoted
      LOGICAL, DIMENSION(:), POINTER                     :: l_val_p
      REAL(kind=dp)                                      :: r_val
      REAL(kind=dp), DIMENSION(:), POINTER               :: r_val_p
      TYPE(cp_sll_char_type), POINTER                    :: c_first, c_last, c_new
      TYPE(cp_sll_int_type), POINTER                     :: i_first, i_last, i_new
      TYPE(cp_sll_logical_type), POINTER                 :: l_first, l_last, l_new
      TYPE(cp_sll_real_type), POINTER                    :: r_first, r_last, r_new

      CALL timeset(routineN, handle)

      CPASSERT(.NOT. ASSOCIATED(val))
      SELECT CASE (type_of_var)
      CASE (no_t)
      CASE (logical_t)
         NULLIFY (l_val_p)
         IF (parser_test_next_token(parser) == "EOL") THEN
            IF (.NOT. ASSOCIATED(default_value)) THEN
               IF (n_var < 1) THEN
                  ALLOCATE (l_val_p(0))
                  CALL val_create(val, l_vals_ptr=l_val_p)
               ELSE
                  CALL cp_abort(__LOCATION__, &
                                "no value was given and there is no default value"// &
                                TRIM(parser_location(parser)))
               END IF
            ELSE
               CPASSERT(ASSOCIATED(default_value%l_val))
               CALL val_create(val, l_vals=default_value%l_val)
            END IF
         ELSE
            IF (n_var < 1) THEN
               NULLIFY (l_last, l_first)
               CALL parser_get_object(parser, l_val)
               CALL cp_create(l_first, l_val)
               l_last => l_first
               DO WHILE (parser_test_next_token(parser) /= "EOL")
                  CALL parser_get_object(parser, l_val)
                  CALL cp_create(l_new, l_val)
                  l_last%rest => l_new
                  l_last => l_new
               END DO
               l_val_p => cp_to_array(l_first)
               CALL cp_dealloc(l_first)
            ELSE
               ALLOCATE (l_val_p(n_var))
               DO i = 1, n_var
                  CALL parser_get_object(parser, l_val_p(i))
               END DO
            END IF
            IF (ASSOCIATED(l_val_p)) THEN
               CALL val_create(val, l_vals_ptr=l_val_p)
            END IF
         END IF
      CASE (integer_t)
         NULLIFY (i_val_p)
         IF (parser_test_next_token(parser) == "EOL") THEN
            IF (.NOT. ASSOCIATED(default_value)) THEN
               IF (n_var < 1) THEN
                  ALLOCATE (i_val_p(0))
                  CALL val_create(val, i_vals_ptr=i_val_p)
               ELSE
                  CALL cp_abort(__LOCATION__, &
                                "no value was given and there is no default value"// &
                                TRIM(parser_location(parser)))
               END IF
            ELSE
               check = ASSOCIATED(default_value%i_val)
               CPASSERT(check)
               CALL val_create(val, i_vals=default_value%i_val)
            END IF
         ELSE
            IF (n_var < 1) THEN
               NULLIFY (i_last, i_first)
               CALL parser_get_object(parser, i_val)
               CALL cp_create(i_first, i_val)
               i_last => i_first
               DO WHILE (parser_test_next_token(parser) /= "EOL")
                  CALL parser_get_object(parser, i_val)
                  CALL cp_create(i_new, i_val)
                  i_last%rest => i_new
                  i_last => i_new
               END DO
               i_val_p => cp_to_array(i_first)
               CALL cp_dealloc(i_first)
            ELSE
               ALLOCATE (i_val_p(n_var))
               DO i = 1, n_var
                  CALL parser_get_object(parser, i_val_p(i))
               END DO
            END IF
            IF (ASSOCIATED(i_val_p)) THEN
               CALL val_create(val, i_vals_ptr=i_val_p)
            END IF
         END IF
      CASE (real_t)
         NULLIFY (r_val_p)
         IF (parser_test_next_token(parser) == "EOL") THEN
            IF (.NOT. ASSOCIATED(default_value)) THEN
               IF (n_var < 1) THEN
                  ALLOCATE (r_val_p(0))
                  CALL val_create(val, r_vals_ptr=r_val_p)
               ELSE
                  CALL cp_abort(__LOCATION__, &
                                "no value was given and there is no default value"// &
                                TRIM(parser_location(parser)))
               END IF
            ELSE
               CPASSERT(ASSOCIATED(default_value%r_val))
               CALL val_create(val, r_vals=default_value%r_val)
            END IF
         ELSE
            IF (n_var < 1) THEN
               NULLIFY (r_last, r_first)
               c_val = ""
               CALL get_r_val(r_val, parser, unit, default_units, c_val)
               CALL cp_create(r_first, r_val)
               r_last => r_first
               DO WHILE (parser_test_next_token(parser) /= "EOL")
                  CALL get_r_val(r_val, parser, unit, default_units, c_val)
                  CALL cp_create(r_new, r_val)
                  r_last%rest => r_new
                  r_last => r_new
               END DO
               NULLIFY (r_last)
               r_val_p => cp_to_array(r_first)
               CALL cp_dealloc(r_first)
            ELSE
               ALLOCATE (r_val_p(n_var))
               c_val = ""
               DO i = 1, n_var
                  CALL get_r_val(r_val_p(i), parser, unit, default_units, c_val)
               END DO
            END IF
            IF (ASSOCIATED(r_val_p)) THEN
               CALL val_create(val, r_vals_ptr=r_val_p)
            END IF
         END IF
      CASE (char_t)
         NULLIFY (c_val_p)
         IF (parser_test_next_token(parser) == "EOL") THEN
            IF (n_var < 1) THEN
               ALLOCATE (c_val_p(1))
               c_val_p(1) = ' '
               CALL val_create(val, c_vals_ptr=c_val_p)
            ELSE
               IF (.NOT. ASSOCIATED(default_value)) THEN
                  CALL cp_abort(__LOCATION__, &
                                "no value was given and there is no default value"// &
                                TRIM(parser_location(parser)))
               ELSE
                  CPASSERT(ASSOCIATED(default_value%c_val))
                  CALL val_create(val, c_vals=default_value%c_val)
               END IF
            END IF
         ELSE
            IF (n_var < 1) THEN
               CPASSERT(n_var == -1)
               NULLIFY (c_last, c_first)
               CALL parser_get_object(parser, c_val)
               CALL cp_create(c_first, c_val)
               c_last => c_first
               DO WHILE (parser_test_next_token(parser) /= "EOL")
                  CALL parser_get_object(parser, c_val)
                  CALL cp_create(c_new, c_val)
                  c_last%rest => c_new
                  c_last => c_new
               END DO
               c_val_p => cp_to_array(c_first)
               CALL cp_dealloc(c_first)
            ELSE
               ALLOCATE (c_val_p(n_var))
               DO i = 1, n_var
                  CALL parser_get_object(parser, c_val_p(i))
               END DO
            END IF
            IF (ASSOCIATED(c_val_p)) THEN
               CALL val_create(val, c_vals_ptr=c_val_p)
            END IF
         END IF
      CASE (lchar_t)
         IF (ASSOCIATED(default_value)) &
            CALL cp_abort(__LOCATION__, &
                          "input variables of type lchar_t cannot have a lone keyword attribute,"// &
                          " no value is interpreted as empty string"// &
                          TRIM(parser_location(parser)))
         IF (n_var /= 1) &
            CALL cp_abort(__LOCATION__, &
                          "input variables of type lchar_t cannot be repeated,"// &
                          " one always represent a whole line, till the end"// &
                          TRIM(parser_location(parser)))
         IF (parser_test_next_token(parser) == "EOL") THEN
            ALLOCATE (c_val_p(1))
            c_val_p(1) = ' '
         ELSE
            NULLIFY (c_last, c_first)
            CALL parser_get_object(parser, c_val, string_length=LEN(c_val))
            IF (c_val(1:1) == parser%quote_character) THEN
               quoted = .TRUE.
               c_val(1:) = c_val(2:) ! Drop first quotation mark
               i = INDEX(c_val, parser%quote_character) ! Check for second quotation mark
               IF (i > 0) THEN
                  c_val(i:) = "" ! Discard stuff after second quotation mark
                  eol = .TRUE. ! Enforce end of line
               ELSE
                  eol = .FALSE.
               END IF
            ELSE
               quoted = .FALSE.
               eol = .FALSE.
            END IF
            CALL cp_create(c_first, c_val)
            c_last => c_first
            DO WHILE ((.NOT. eol) .AND. (parser_test_next_token(parser) /= "EOL"))
               CALL parser_get_object(parser, c_val, string_length=LEN(c_val))
               i = INDEX(c_val, parser%quote_character) ! Check for quotation mark
               IF (i > 0) THEN
                  IF (quoted) THEN
                     c_val(i:) = "" ! Discard stuff after second quotation mark
                     eol = .TRUE. ! Enforce end of line
                  ELSE
                     CALL cp_abort(__LOCATION__, &
                                   "Quotation mark found which is not the first non-blank character. "// &
                                   "Possibly the first quotation mark is missing?"// &
                                   TRIM(parser_location(parser)))
                  END IF
               ELSE
                  eol = .FALSE.
               END IF
               CALL cp_create(c_new, c_val)
               c_last%rest => c_new
               c_last => c_new
            END DO
            c_val_p => cp_to_array(c_first)
            CALL cp_dealloc(c_first)
         END IF
         CPASSERT(ASSOCIATED(c_val_p))
         CALL val_create(val, lc_vals_ptr=c_val_p)
      CASE (enum_t)
         CPASSERT(ASSOCIATED(enum))
         NULLIFY (i_val_p)
         IF (parser_test_next_token(parser) == "EOL") THEN
            IF (.NOT. ASSOCIATED(default_value)) THEN
               IF (n_var < 1) THEN
                  ALLOCATE (i_val_p(0))
                  CALL val_create(val, i_vals_ptr=i_val_p)
               ELSE
                  CALL cp_abort(__LOCATION__, &
                                "no value was given and there is no default value"// &
                                TRIM(parser_location(parser)))
               END IF
            ELSE
               CPASSERT(ASSOCIATED(default_value%i_val))
               CALL val_create(val, i_vals=default_value%i_val, &
                               enum=default_value%enum)
            END IF
         ELSE
            IF (n_var < 1) THEN
               NULLIFY (i_last, i_first)
               CALL parser_get_object(parser, c_val)
               CALL cp_create(i_first, enum_c2i(enum, c_val))
               i_last => i_first
               DO WHILE (parser_test_next_token(parser) /= "EOL")
                  CALL parser_get_object(parser, c_val)
                  CALL cp_create(i_new, enum_c2i(enum, c_val))
                  i_last%rest => i_new
                  i_last => i_new
               END DO
               i_val_p => cp_to_array(i_first)
               CALL cp_dealloc(i_first)
            ELSE
               ALLOCATE (i_val_p(n_var))
               DO i = 1, n_var
                  CALL parser_get_object(parser, c_val)
                  i_val_p(i) = enum_c2i(enum, c_val)
               END DO
            END IF
            IF (ASSOCIATED(i_val_p)) THEN
               CALL val_create(val, i_vals_ptr=i_val_p, enum=enum)
            END IF
         END IF
      CASE default
         CALL cp_abort(__LOCATION__, &
                       "type "//cp_to_string(type_of_var)//"unknown to the parser")
      END SELECT
      IF (parser_test_next_token(parser) .NE. "EOL") THEN
         location = TRIM(parser_location(parser))
         CALL parser_get_object(parser, info)
         CALL cp_abort(__LOCATION__, &
                       "found unexpected extra argument "//TRIM(info)//" at "//location)
      END IF

      CALL timestop(handle)

   END SUBROUTINE val_create_parsing

! **************************************************************************************************
!> \brief Reads and convert a real number from the input file
!> \param r_val ...
!> \param parser the parser from where the values should be read
!> \param unit ...
!> \param default_units ...
!> \param c_val ...
!> \author Teodoro Laino - 11.2007 [tlaino] - University of Zurich
! **************************************************************************************************
   SUBROUTINE get_r_val(r_val, parser, unit, default_units, c_val)
      REAL(kind=dp), INTENT(OUT)                         :: r_val
      TYPE(cp_parser_type), INTENT(INOUT)                :: parser
      TYPE(cp_unit_type), POINTER                        :: unit
      TYPE(cp_unit_set_type), INTENT(IN)                 :: default_units
      CHARACTER(len=default_string_length), &
         INTENT(INOUT)                                   :: c_val

      TYPE(cp_unit_type), POINTER                        :: my_unit

      NULLIFY (my_unit)
      IF (ASSOCIATED(unit)) THEN
         IF ('STR' == parser_test_next_token(parser)) THEN
            CALL parser_get_object(parser, c_val)
            IF (c_val(1:1) /= "[" .OR. c_val(LEN_TRIM(c_val):LEN_TRIM(c_val)) /= "]") THEN
               CALL cp_abort(__LOCATION__, &
                             "Invalid unit specifier or function found when parsing a number: "// &
                             c_val)
            END IF
            ALLOCATE (my_unit)
            CALL cp_unit_create(my_unit, c_val(2:LEN_TRIM(c_val) - 1))
         ELSE
            IF (c_val /= "") THEN
               ALLOCATE (my_unit)
               CALL cp_unit_create(my_unit, c_val(2:LEN_TRIM(c_val) - 1))
            ELSE
               my_unit => unit
            END IF
         END IF
         IF (.NOT. cp_unit_compatible(unit, my_unit)) &
            CALL cp_abort(__LOCATION__, &
                          "Incompatible units. Defined as ("// &
                          TRIM(cp_unit_desc(unit))//") specified in input as ("// &
                          TRIM(cp_unit_desc(my_unit))//"). These units are incompatible!")
      END IF
      CALL parser_get_object(parser, r_val)
      IF (ASSOCIATED(unit)) THEN
         r_val = cp_unit_to_cp2k1(r_val, my_unit, default_units)
         IF (.NOT. (ASSOCIATED(my_unit, unit))) THEN
            CALL cp_unit_release(my_unit)
            DEALLOCATE (my_unit)
         END IF
      END IF

   END SUBROUTINE get_r_val

END MODULE input_parsing
