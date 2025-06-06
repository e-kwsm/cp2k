!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief Datatype to translate between k-points (2d) and gamma-point (1d) code.
!> \note  In principle storing just the 2d pointer would be sufficient.
!>        However due to a bug in ifort with the deallocation of
!>        bounds-remapped pointers, we also have to store the original
!>        1d pointer used for allocation.
!>
!> \par History
!>      11.2014 created [Ole Schuett]
!> \author Ole Schuett
! **************************************************************************************************
MODULE kpoint_transitional
   USE cp_dbcsr_api,                    ONLY: dbcsr_p_type
   USE cp_dbcsr_operations,             ONLY: dbcsr_deallocate_matrix_set
#include "./base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE

   PUBLIC :: kpoint_transitional_type, kpoint_transitional_release
   PUBLIC :: get_1d_pointer, get_2d_pointer, set_1d_pointer, set_2d_pointer

   TYPE kpoint_transitional_type
      PRIVATE
      TYPE(dbcsr_p_type), DIMENSION(:), POINTER          :: ptr_1d => Null()
      TYPE(dbcsr_p_type), DIMENSION(:, :), POINTER        :: ptr_2d => Null()
      LOGICAL                                               :: set_as_1d = .FALSE.
   END TYPE kpoint_transitional_type

CONTAINS

! **************************************************************************************************
!> \brief Smart getter, raises an error when called during a k-point calculation
!> \param this ...
!> \return ...
!> \author Ole Schuett
! **************************************************************************************************
   FUNCTION get_1d_pointer(this) RESULT(res)
      TYPE(kpoint_transitional_type)                     :: this
      TYPE(dbcsr_p_type), DIMENSION(:), POINTER          :: res

      IF (ASSOCIATED(this%ptr_1d)) THEN
         IF (SIZE(this%ptr_2d, 2) /= 1) &
            CPABORT("Method not implemented for k-points")
      END IF

      res => this%ptr_1d
   END FUNCTION get_1d_pointer

! **************************************************************************************************
!> \brief Simple getter, needed because of PRIVATE
!> \param this ...
!> \return ...
!> \author Ole Schuett
! **************************************************************************************************
   FUNCTION get_2d_pointer(this) RESULT(res)
      TYPE(kpoint_transitional_type)                     :: this
      TYPE(dbcsr_p_type), DIMENSION(:, :), POINTER       :: res

      res => this%ptr_2d
   END FUNCTION get_2d_pointer

! **************************************************************************************************
!> \brief Assigns a 1D pointer
!> \param this ...
!> \param ptr_1d ...
!> \author Ole Schuett
! **************************************************************************************************
   SUBROUTINE set_1d_pointer(this, ptr_1d)
      TYPE(kpoint_transitional_type)                     :: this
      TYPE(dbcsr_p_type), DIMENSION(:), POINTER          :: ptr_1d

      INTEGER                                            :: n

      IF (ASSOCIATED(ptr_1d)) THEN
         n = SIZE(ptr_1d)
         this%ptr_1d => ptr_1d
         this%ptr_2d(1:n, 1:1) => ptr_1d
         this%set_as_1d = .TRUE.
      ELSE
         this%ptr_1d => Null()
         this%ptr_2d => Null()
      END IF
   END SUBROUTINE set_1d_pointer

! **************************************************************************************************
!> \brief Assigns a 2D pointer
!> \param this ...
!> \param ptr_2d ...
!> \author Ole Schuett
! **************************************************************************************************
   SUBROUTINE set_2d_pointer(this, ptr_2d)
      TYPE(kpoint_transitional_type)                     :: this
      TYPE(dbcsr_p_type), DIMENSION(:, :), POINTER       :: ptr_2d

      IF (ASSOCIATED(ptr_2d)) THEN
         this%ptr_1d => ptr_2d(:, 1)
         this%ptr_2d => ptr_2d
         this%set_as_1d = .FALSE.
      ELSE
         this%ptr_1d => Null()
         this%ptr_2d => Null()
      END IF
   END SUBROUTINE set_2d_pointer

! **************************************************************************************************
!> \brief Release the matrix set, using the right pointer
!> \param this ...
!> \author Ole Schuett
! **************************************************************************************************
   SUBROUTINE kpoint_transitional_release(this)
      TYPE(kpoint_transitional_type)                     :: this

      IF (ASSOCIATED(this%ptr_1d)) THEN
         IF (this%set_as_1d) THEN
            CALL dbcsr_deallocate_matrix_set(this%ptr_1d)
         ELSE
            CALL dbcsr_deallocate_matrix_set(this%ptr_2d)
         END IF
      END IF
      NULLIFY (this%ptr_1d, this%ptr_2d)
   END SUBROUTINE kpoint_transitional_release

END MODULE kpoint_transitional
